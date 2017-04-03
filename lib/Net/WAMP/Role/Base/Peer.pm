package Net::WAMP::Role::Base::Peer;

use strict;
use warnings;

use Module::Load ();

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

#or else send “wamp.error.invalid_uri”
#WAMP’s specification gives: re.compile(r"^([^\s\.#]+\.)*([^\s\.#]+)$")

sub _validate_uri {
    my ($self, $specimen) = @_;

    if ($specimen =~ m<\.\.>o) {
        die Net::WAMP::X->create('BadURI', 'empty URI component', $specimen);
    }

    if (0 == index($specimen, '.')) {
        die Net::WAMP::X->create('BadURI', 'initial “.”', $specimen);
    }

    if (substr($specimen, -1) eq '.') {
        die Net::WAMP::X->create('BadURI', 'trailing “.”', $specimen);
    }

    if ($specimen =~ tr<#><>) {
        die Net::WAMP::X->create('BadURI', '“#” is forbidden', $specimen);
    }

    #XXX https://github.com/wamp-proto/wamp-proto/issues/275
    if ($specimen =~ m<\s>o) {
        die Net::WAMP::X->create('BadURI', 'Whitespace is forbidden.', $specimen);
    }

    return;
}

#XXX De-duplicate TODO
sub _create_msg {
    my ($self, $name, @parts) = @_;

    my $mod = "Net::WAMP::Message::$name";
    Module::Load::load($mod) if !$mod->can('new');

    return $mod->new(@parts);
}

#This happens during handshake.
sub _receive_ABORT {
    my ($self, $msg) = @_;

    #die "$msg: " . $self->_stringify($msg);   #XXX

    return;
}

1;
