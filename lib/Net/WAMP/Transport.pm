package Net::WAMP::Transport;

#Subclasses must implement:
#
#   - _serialized_wamp_to_transport_bytes
#   - _read_transport_message
#

use strict;
use warnings;

use IO::SigGuard ();
use Module::Load ();

use Net::WAMP::Messages ();
use Net::WAMP::X ();

use constant CONSTRUCTOR_OPTS => ();

use constant IO_BASE = 'Net::WAMP::Transport::IO';

#We require “serialization” here.
sub new {
    my ($class, %opts) = @_;

    #Convenience?
    #if ('ARRAY' eq ref $io) {
    #    my $io_mod = "Net::WAMP::Transport::IO::$io->[0]";
    #    Module::Load::load($io_mod) if !$io_mod->can('new');
    #    $io = $io_mod->new( @{$io}[ 1 .. $#$io ] );
    #}

    my $self = {
        ( map { ( "_$_" => $opts{$_} ) } $class->CONSTRUCTOR_OPTS() ),

        _last_session_scope_id => 0,
    };

    bless $self, $class;

    my $serialization = $opts{'serialization'} or die 'Need “serialization”!';

    $self->_set_serialization_format($serialization);

    return $self;
}

sub write_wamp_message {
    my ($self, $wamp_msg) = @_;

    $self->_verify_not_shut_down();

    my $wamp_bytes = $self->_stringify( $wamp_msg->to_unblessed() );

    $self->_write_bytes(
        $self->_serialized_wamp_to_transport_bytes($wamp_bytes),
    );

    return;
}

sub read_wamp_message {
    my ($self) = @_;

    $self->_verify_not_shut_down();

    my $array_ref = $self->_destringify(

        #avoid creating the variable
        ($self->_read_transport_message() or return undef),
    );

    my $type_num = shift(@$array_ref);
    my $type = Net::WAMP::Messages::get_type($type_num);

    my $msg = $self->_create_msg( $type, @$array_ref );

    if ($msg->isa('Net::WAMP::Base::SessionMessage')) {
        my $ss_id = $msg->get( $msg->SESSION_SCOPE_ID_ELEMENT() );

        if ( $ss_id != 1 + $self->{'_last_session_scope_id'} ) {

            #XXX TODO - Wampy.js is probably not the only client that screws this up.
            #die "Last-sent scope ID is “$self->{'_last_session_scope_id'}”; received “$ss_id”. (Should increment by 1!)";
        }

        $self->{'_last_session_scope_id'} = $ss_id;
    }

    return $msg;
}

sub get_next_session_scope_id {
    my ($self) = @_;

    return ++$self->{'_last_session_scope_id'};
}



#----------------------------------------------------------------------





sub _set_shutdown {
    shift()->{'_shutdown_happened'} = 1;
    return;
}

sub _is_shut_down {
    my ($self) = @_;

    return $self->{'_shutdown_happened'} ? 1 : 0;
}

sub _verify_not_shut_down {
    my ($self) = @_;

    if ($self->{'_shutdown_happened'}) {
        die "$self is already shut down!";
    }

    return;
}

1;
