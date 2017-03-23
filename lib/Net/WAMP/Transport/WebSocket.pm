package Net::WAMP::Transport::WebSocket;

use strict;
use warnings;

use parent qw(
    Net::WAMP::Transport
    Net::WAMP::Transport::Base::Handshaker
);

use Module::Load ();

use Net::WAMP::X ();

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

print "read endpoint\n";
    my $msg = eval { $self->{'_endpoint'}->get_next_message() };
print "did read endpoint\n";

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
