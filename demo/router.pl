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

#XXX FIXME
use lib "$FindBin::Bin/../../p5-Net-WebSocket/lib";

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

use Data::Dumper;
print STDERR Dumper("to write", \%fd_io, @to_write) if @to_write;
    my $wselect = @to_write ? IO::Select->new(@to_write) : undef;
#print STDERR Dumper('wsel', $wselect, \%fd_sess);
use Data::Dumper;
#print STDERR Dumper('select handles', $select->handles());

    my ($rdrs_ar, $wtrs_ar, $errs_ar) = IO::Select->select( $select, $wselect, $select, 5 );

    if (!$rdrs_ar) {
#print STDERR "timeout\n";
next;
print STDERR Dumper('heartbeat', \%fd_sess);
        for my $sess (values %fd_sess) {
            next if !$sess->{'heartbeat'};
            $sess->{'heartbeat'}->();

            if ( $sess->{'type'} eq 'websocket' ) {
                for ( 1 .. $sess->{'xport'}->get_write_queue_size() ) {
                    $sess->{'io'}->enqueue_write( $sess->{'xport'}->shift_write_queue()->to_bytes() );
                }
            }
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
printf STDERR "read: %d\n", fileno $fh;
        if ($fh == $server) {
            accept( my $connection, $server );

            $connection->blocking(0);
            $select->add($connection);

        }

        #A successful connection creates an IO object.
        elsif (my $sess = $fd_sess{fileno $fh}) {
            my $msg;

            try {
                if ($sess->{'type'} eq 'websocket') {
                    if ($sess->{'io'}) {
                        $msg = $sess->{'xport'}->get_next_message();
                    }
                    else {
                        _consume_handshake($fh, $sess);
                    }
                }
                elsif ($sess->{'type'} eq 'rawsocket') {
                    if ($sess->{'did_handshake'}) {

                        $msg = $sess->{'xport'}->get_next_message();
                    }
                    else {
                        $sess->{'xport'}->receive_and_answer_handshake() or next FH;
                        $sess->{'did_handshake'} = 1;

                        $sess->{'session'} = Net::WAMP::Session->new(
                            $sess->{'xport'}->get_serialization(),
                        );
                    }
                }
                else { die "huh?" }
            }
            catch {
                my $done = try { $_->isa('IO::Framed::X::EmptyRead') };
                $done ||= try { $_->isa('Net::WebSocket::X::ReceivedClose') };

                if ($done) {
                    _remove_fh_session($fh);
                }
                else {
                    local $@ = $_;
                    die;
                }
            };

            #transport-agnostic
            if ($msg) {
                $msg = $sess->{'session'}->message_bytes_to_object($msg->get_payload());
                $router->route_message($msg, $sess->{'session'});
            }

            _collect_session_messages();
        }

        #No IO object? Then something’s wrong!
        else {
            #die sprintf("Unknown read ($fh, fd %d)\n", fileno $fh);

            #my $conn = $fd_connection{fileno $fh};

            my $tpt;
            if ( Net::WAMP::RawSocket::Check::is_rawsocket($fh) ) {
                Module::Load::load('Net::WAMP::RawSocket::Server');
                my $io = _create_io($fh);

                my $rs = Net::WAMP::RawSocket::Server->new( io => $io );

                $fd_sess{fileno $fh} = {
                    io => $io,
                    type => 'rawsocket',
                    xport => $rs,
                    heartbeat => sub { $rs->check_heartbeat() },
                };
            }
            else {
                Module::Load::load('Net::WebSocket::Handshake::Server');
                Module::Load::load('Net::WebSocket::Endpoint::Server');
                Module::Load::load('Net::WebSocket::Parser');

                IO::SigGuard::sysread( $fh, my $buf, 32768 ) or die $!; #XXX
use Data::Dumper;
print STDERR Dumper('WebSocket headers received', $buf);

                $fd_sess{fileno $fh} = {
                    type => 'websocket',
                    hsk_buf => $buf,
                };

                _consume_handshake($fh, $fd_sess{fileno $fh});

                #die 'No WebSocket yet …';
                #$tpt = Net::WAMP::Transport::WebSocket::Server->new( ($conn) x 2 );
            }

            #$fd_tpt{fileno $fh} = $tpt;
            #$tpt_fh{$tpt} = $fh;
        }
    }

    for my $fh ( @$errs_ar ) {
        printf STDERR "FD %d error!\n", fileno($fh);
        _remove_fh_session($fh);
    }
}

sub _remove_fh_session {
    my ($fh) = @_;

    $select->remove($fh);
    delete $fd_io{fileno $fh};

    if (my $sess = delete $fd_sess{fileno $fh}) {
        $router->forget_session($sess->{'session'});
        delete $io_fh{$sess->{'io'}};
    }

    close $fh;
}

sub _collect_session_messages {
    for my $sess (values %fd_sess) {
        while (my $serlzd = $sess->{'session'}->shift_message_queue()) {
            if ($sess->{'type'} eq 'rawsocket') {
                $sess->{'xport'}->send_message($serlzd);
            }
            else {
                #XXX FIXME
                use Net::WebSocket::Frame::text ();
                my $frame = Net::WebSocket::Frame::text->new(
                    payload_sr => \$serlzd,
                );

                $sess->{'io'}->enqueue_write( $frame->to_bytes() );
            }
        }
    }
}

sub _create_io {
    my ($fh) = @_;

    my $io = IO::Framed::NonBlocking->new($fh, $fh);
    $fd_io{fileno $fh} = $io;
    $io_fh{$io} = $fh;
    return $io;
}

sub _consume_handshake {
    my ($fh, $sess_hr) = @_;

    use IO::SigGuard ();
    my $idx = index($sess_hr->{'hsk_buf'}, "\x0d\x0a\x0d\x0a");

    return if $idx == -1;

    my $buf = substr( $sess_hr->{'hsk_buf'}, 0, 4 + $idx, q<> );

    $buf =~ m<-Key:\s+(\S+)>m or die "no key";
    my $key = $1;

    $buf =~ m<Protocol.+wamp\.2\.(\S+)> or die "no protocol";
    my $serialization = $1;

    my $hsk = Net::WebSocket::Handshake::Server->new(

        #required, base 64
        key => $key,

        #optional
        subprotocols => [ "wamp.2.$serialization" ],  #XXX FIXME
    );

    my $ep = Net::WebSocket::Endpoint::Server->new(
        parser => Net::WebSocket::Parser->new($fh),
    );

    my $io = _create_io($fh);

    @{$sess_hr}{ 'xport', 'io', 'heartbeat', 'session' } = (
        $ep,
        $io,
        sub { $ep->check_heartbeat() },
        Net::WAMP::Session->new($serialization),
    );

    $io->enqueue_write($hsk->create_header_text() . "\x0d\x0a");

    return;
}

1;
