package Net::WAMP::Peer;

use strict;
use warnings;

#----------------------------------------------------------------------

sub _get_message_handlers {
    my ($self, $msg) = @_;

    #$self->_verify_handshake();

    my $type = $msg->get_type();

    my $handler_cr = $self->can("_receive_$type");
    if (!$handler_cr) {
        die "“$self” received a message of type “$type” but cannot handle messages of this type!";
    }

    my $handler2_cr = $self->can("on_$type");

    return ($handler_cr, $handler2_cr);
}

sub _verify_handshake {
    my ($self) = @_;

    die "Need WAMP handshake first!" if !$self->{'_handshake_done'};

    return;
}

#XXX De-duplicate TODO
sub _create_msg {
    my ($self, $name, @parts) = @_;

    my $mod = "Protocol::WAMP::Message::$name";
    Module::Load::load($mod) if !$mod->can('new');

    return $mod->new(@parts);
}

sub _receive_ABORT {
    my ($self, $msg) = @_;

    die "$msg: " . $self->_stringify($msg);   #XXX

    return;
}

#Anything can receive an ERROR or an ABORT.
#We’ll eventually want more fine-grained ERROR handling.
*_receive_ERROR = *_receive_ABORT;

1;
