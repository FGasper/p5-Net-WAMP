#!/usr/bin/env perl

#----------------------------------------------------------------------
package MyRouter;

use FindBin;
use lib "$FindBin::Bin/../lib";

use parent qw(
    Net::WAMP::Role::Dealer
    Net::WAMP::Role::Broker
);

#----------------------------------------------------------------------
package main;

use strict;
use warnings;
use autodie;

use Try::Tiny;

my ($ip, $port);

if ( my $ip_port = $ARGV[0] ) {

    ($ip, $port) = $ip_port =~ m<(?:(.+):)?([0-9]+)>;
}

use Carp::Always;

die "Need [ip:]port!" if !$port;

use IO::Framed::NonBlocking ();

use IO::Socket::INET;
my $server = IO::Socket::INET->new(
    LocalAddr => $ip,
    LocalPort => $port,
    Listen => 5,
    ReuseAddr => 1,
);
die "server: [$@][$!]" if !$server;

#$server->blocking(0);

printf STDERR "server fd: %d\n", fileno($server);

use IO::Select;
my $select = IO::Select->new( $server );

my %fd_io;
my %io_fh;

my $router = MyRouter->new();

use Net::WAMP::RawSocket::Check ();
use Net::WAMP::Session ();

#my %fd_connection;
my %fd_sess;

#TODO handle select exception events
while (1) {
    my @to_write = grep { $_->get_write_queue_size() } values %fd_io;
    $_ = $io_fh{$_} for @to_write;

    my $wselect = @to_write ? IO::Select->new(@to_write) : undef;

    my ($rdrs_ar, $wtrs_ar, $errs_ar) = IO::Select->select( $select, $wselect, $select, 5 );

    if (!$rdrs_ar) {
        for my $sess (values %fd_sess) {
            $sess->{'heartbeat'}->() if $sess->{'heartbeat'};
        }

        next;
    }

    if ($wtrs_ar) {
        for my $fh (@$wtrs_ar) {
            $fd_io{ fileno $fh }->flush_write_queue();
        }
    }

  FH:
    for my $fh (@$rdrs_ar) {
        if ($fh == $server) {
            accept( my $connection, $server );

            $connection->blocking(0);
            $select->add($connection);
        }

        #A successful connection creates an IO object.
        elsif (my $sess = $fd_sess{fileno $fh}) {
            my $msg;

            if ($sess->{'type'} eq 'rawsocket') {
                if ($sess->{'did_handshake'}) {

                    try {
                        $msg = $sess->{'xport'}->get_next_message();
                        $msg &&= $sess->{'session'}->message_bytes_to_object($msg->get_payload());
                    }
                    catch {
                        my $done = try { $_->isa('IO::Framed::X::EmptyRead') };
                        $done ||= try { $_->isa('Net::WebSocket::X::ReceivedClose') };

                        if ($done) {
                            $router->forget_session($sess->{'session'});
                            $select->remove($fh);
                            delete $fd_io{fileno $fh};
                            delete $fd_sess{fileno $fh};
                            delete $io_fh{$sess->{'io'}};
                            close $fh;
                        }
                        else {
                            local $@ = $_;
                            die;
                        }
                    };
                }
                else {
                    $sess->{'xport'}->receive_and_answer_handshake() or next FH;
                    $sess->{'did_handshake'} = 1;

                    $sess->{'session'} = Net::WAMP::Session->new(
                        $sess->{'xport'}->get_serialization(),
                    );
                }

#            if ($tpt->did_handshake()) {
#                my $msg;
#                try {
#                    $msg = $tpt->read_wamp_message();
#                }
#                catch {
#                    my $done = try { $_->isa('Net::WAMP::X::EmptyRead') };
#                    $done ||= try { $_->isa('Net::WebSocket::X::ReceivedClose') };
#
#                    if ($done) {
#                        $router->forget_transport($tpt);
#                        $select->remove($fh);
#                        delete $fd_tpt{fileno $fh};
#                        delete $fd_connection{fileno $fh};
#                        delete $tpt_fh{$tpt};
#                        close $fh;
#                    }
#                    else {
#                        local $@ = $_;
#                        die;
#                    }
#                };


            }
#            else {
#                $tpt->handshake();
#            }

            #transport-agnostic
            if ($msg) {
                $router->route_message($msg, $sess->{'session'});

                while (my $serlzd = $sess->{'session'}->shift_message_queue()) {
                    $sess->{'xport'}->send_message($serlzd);
                }
            }
        }

        #No IO object? Then something’s wrong!
        else {
            #die sprintf("Unknown read ($fh, fd %d)\n", fileno $fh);

            #my $conn = $fd_connection{fileno $fh};

            my $tpt;
            if ( Net::WAMP::RawSocket::Check::is_rawsocket($fh) ) {
                Module::Load::load('Net::WAMP::RawSocket::Server');
                my $io = IO::Framed::NonBlocking->new($fh, $fh);
                $fd_io{fileno $fh} = $io;
                $io_fh{$io} = $fh;

                my $rs = Net::WAMP::RawSocket::Server->new( io => $io );

                $fd_sess{fileno $fh} = {
                    io => $io,
                    type => 'rawsocket',
                    xport => $rs,
                    heartbeat => sub { $rs->check_heartbeat() },
                };
            }
            else {
                die 'No WebSocket yet …';
                #Module::Load::load('Net::WebSocket::Endpoint::Server');
                #$tpt = Net::WAMP::Transport::WebSocket::Server->new( ($conn) x 2 );
            }

            #$fd_tpt{fileno $fh} = $tpt;
            #$tpt_fh{$tpt} = $fh;
        }
    }

    for my $fh ( @$errs_ar ) {
        printf STDERR "FD %d error!\n", fileno($fh);
        $select->remove($fh);
        close $fh;
    }
}

1;
