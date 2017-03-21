package Net::WAMP::IO::WebSocket;

use strict;
use warnings;

use parent 'Net::WAMP::IO';

use Module::Load ();

use Net::WAMP::X ();

sub new {
    my ($class, $in_fh, $out_fh) = @_;

    my $self = $class->SUPER::new();

    @{$self}{ qw( _in_fh  _out_fh  _message_type ) } = (
        $in_fh,
        $out_fh,
        undef,
    );

    return $self;
}

sub _verify_handshake_not_done {
    my ($self) = @_;

    die "Already did handshake!" if $self->{'_handshake_done'};

    return;
}

sub _set_serialization_format {
    my ($self, @args) = @_;

    $self->SUPER::_set_serialization_format(@args);

    $self->{'_message_type'} = $self->_get_websocket_message_type();

    return $self;
}

sub _get_websocket_message_type {
    my ($self) = @_;

    return $self->{'_serialization_module'}->websocket_message_type();
}

sub did_handshake {
    my ($self) = @_;

    return $self->{'_handshake_done'} ? 1 : 0;
}

sub _serialized_wamp_to_transport_bytes {
    my ($self, $wamp_bytes) = @_;

    if (!$self->{'_message_type'}) {
        die "Message type not set!";
    }

    my $creator_class = "Net::WebSocket::Frame::$self->{'_message_type'}";

    Module::Load::load($creator_class) if !$creator_class->can('new');

    my $ws_msg = $creator_class->new(
        payload_sr => \$wamp_bytes,
        $self->FRAME_MASK_ARGS(),
    );

    return $ws_msg->to_bytes();
}

my $_last_err;

sub _read_transport_message {
    my ($self) = @_;

    $_last_err = $@;

    my $msg = eval { $self->{'_endpoint'}->get_next_message() };

    if ($@) {
        my $err = $@;
        if ( eval { $err->isa('Net::WebSocket::X::EmptyRead') } ) {
            die Net::WAMP::X->create('EmptyRead');
        }

        $@ = $err;
        die;
    }

    $@ = $_last_err;

    return $msg && $msg->get_payload();
}

1;
