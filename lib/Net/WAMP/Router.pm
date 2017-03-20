package Net::WAMP::Router;

use strict;
use warnings;

use parent qw(
    Net::WAMP::Peer
);

use lib '/Users/felipe/code/p5-Protocol-WAMP/lib';
use Protocol::WAMP::Utils ();

sub new {
    return bless {}, shift;
}

sub route_message {
    my ($self, $msg, $io) = @_;

    my ($handler_cr, $handler2_cr) = $self->_get_message_handlers($msg);

    my @extra_args = $handler_cr->( $self, $msg, $io );
use Data::Dumper;
print STDERR Dumper( 'got', $msg, @extra_args, $handler2_cr );

    #Check for external method definition
    if ($handler2_cr) {
$Data::Dumper::Deparse = 1;
print STDERR Dumper $handler2_cr;
        $handler2_cr->( $self, $msg, $io, @extra_args );
    }

    return $msg;
}

sub send_GOODBYE {
    my ($self, $io, $details, $reason) = @_;

    my $msg = $self->_create_and_send_msg(
        $io,
        'GOODBYE',
        $details,
        $reason,
    );

    $self->{'_sent_GOODBYE'} = 1;

    return $msg;
}

#Subclasses can safely override. They’ll probably want to call into
#this one as well and Hash::Merge their contents.
sub GET_DETAILS_HR {
    my ($self) = @_;

    return { roles => \%Net::WAMP::Router::Features::FEATURES };
}

#----------------------------------------------------------------------

sub _receive_HELLO {
    my ($self, $msg, $io) = @_;

    my $details_hr = $self->GET_DETAILS_HR();

    #TODO: validate HELLO

    my $realm = $msg->get('Realm') or do {
        die "Missing “Realm” in HELLO!";  #XXX
    };

    $self->{'_io_peer_roles'}{$io} = $msg->get('Details')->{'roles'} or do {
        die "Missing “Details.roles” in HELLO!";  #XXX
    };

    #------------------------------

    my $session_id = Protocol::WAMP::Utils::generate_global_id();

    $self->{'_io_session'}{$io} = $session_id;
    $self->{'_io_realm'}{$io} = $realm;

    $self->_send_WELCOME($io, $session_id);

    return;
}

sub _send_WELCOME {
    my ($self, $io, $session) = @_;

print STDERR "SENDING WELCOME\n";
    my $msg = $self->_create_and_send_msg(
        $io,
        'WELCOME',
        $session,
        $self->GET_DETAILS_HR(),
    );

    $self->{'_io_handshake_done'}{$io} = 1;

    return $msg;
}

sub _receive_GOODBYE {
    my ($self, $msg, $io) = @_;

    delete $self->{'_io_session'}{$io} or do {
        die "Got GOODBYE without a registered session!";
    };

    delete $self->{'_io_realm'}{$io};

    if ($self->{'_sent_GOODBYE'}) {
        $self->{'_finished'} = 1;
    }
    else {
        $self->send_GOODBYE( $io, $msg->get('Details'), $msg->get('Reason') );
    }

    return $self;
}

#----------------------------------------------------------------------
# The actual logic to change router state is exposed publicly for the
# sake of applications that may want a “default” router configuration.



#----------------------------------------------------------------------

sub _get_realm_for_io {
    my ($self, $io) = @_;

    return $self->{'_io_realm'}{$io} || do {
        die "No known realm for IO object “$io”!";
    };
}

sub _create_and_send_msg {
    my ($self, $io, $name, @parts) = @_;

    #This is in Peer.pm
    my $msg = $self->_create_msg($name, @parts);

    $self->_send_msg($io, $msg);

    return $msg;
}

sub _send_msg {
    my ($self, $io, $msg) = @_;

    if (!$self->{'_io_session'}{$io}) {
        die "Already finished!";    #XXX
    }

    #cache
    $self->{'_io_peer_groks_msg'}{$io}{$msg->get_type()} ||= do {
#        $self->_verify_receiver_can_accept_msg_type($msg->get_type());
        1;
    };

    $io->write_wamp_message($msg);

    return $self;
}

#----------------------------------------------------------------------
#XXX Copy/paste …

sub io_peer_is {
    my ($self, $io, $role) = @_;

    $self->_verify_handshake();

    return $self->{'_io_peer_roles'}{$role} ? 1 : 0;
}

sub io_peer_role_supports_boolean {
    my ($self, $io, $role, $feature) = @_;

    die "Need role!" if !length $role;
    die "Need feature!" if !length $feature;

    $self->_verify_handshake();

    if ( my $rolfeat = $self->{'_io_peer_roles'}{$io}{$role} ) {
        if ( my $features_hr = $rolfeat->{'features'} ) {
            my $val = $features_hr->{$feature};
            return 0 if !defined $val;

            if (!$val->isa('Types::Serialiser::Boolean')) {
                die "“$role”/“$feature” ($val) is not a boolean value!";
            }

            return $val ? 1 : 0;
        }
    }

    return 0;
}

1;
