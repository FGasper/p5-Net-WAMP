package Net::WAMP::Session;

use strict;
use warnings;

use Net::WAMP::Messages ();

sub new {
    my ($class, %opts) = @_;

    my @missing = grep { !$opts{$_} } qw( serialization  on_send );
    die 'Need “serialization”!' if !$opts{'serialization'};
    die 'Need “on_send”!' if !$opts{'serialization'};

    my $self = bless {
        _last_session_scope_id => 0,
        #_send_queue => [],
        _on_send => $opts{'on_send'},
    }, $class;

    $self->_set_serialization_format($opts{'serialization'});

    return $self;
}

sub send_message {
    $_[0]->{'_on_send'}->( $_[0]->message_object_to_bytes($_[1]) );
    return;
}

sub get_next_session_scope_id {
    my ($self) = @_;

    return ++$self->{'_last_session_scope_id'};
}

sub message_bytes_to_object {
    my ($self) = @_;

    my $array_ref = $self->_destringify($_[1]);

    my $type_num = shift(@$array_ref);
    my $type = Net::WAMP::Messages::get_type($type_num);

    return $self->_create_msg( $type, @$array_ref );
}

sub message_object_to_bytes {
    my ($self, $wamp_msg) = @_;

    return $self->_stringify( $wamp_msg->to_unblessed() );
}

#sub enqueue_message_to_send {
#    my ($self, $msg) = @_;
#
#    push @{ $self->{'_send_queue'} }, $msg;
#
#    return;
#}
#
#sub shift_message_queue {
#    my ($self, $msg) = @_;
#
#    return undef if !@{ $self->{'_send_queue'} };
#
#    return $self->message_object_to_bytes(
#        shift @{ $self->{'_send_queue'} },
#    );
#}

sub shutdown {
    $_[0]{'_is_shut_down'} = 1;
    return;
}

sub is_shut_down {
    return $_[0]{'_is_shut_down'};
}

sub get_serialization {
    my ($self) = @_;

    return $self->{'_serialization'};
}

sub get_websocket_data_type {
    my ($self) = shift;
    return $self->{'_serialization_module'}->websocket_data_type();
}

#----------------------------------------------------------------------

sub _set_serialization_format {
    my ($self, $serialization) = @_;

    my $ser_mod = "Net::WAMP::Serialization::$serialization";
    Module::Load::load($ser_mod) if !$ser_mod->can('stringify');

    $self->{'_serialization'} = $serialization;
    $self->{'_serialization_module'} = $ser_mod;

    return $self;
}

sub _serialization_is_set {
    my ($self) = @_;

    return $self->{'_serialization_module'} ? 1 : 0;
}

sub _stringify {
    my ($self) = shift;
    return $self->{'_serialization_module'}->can('stringify')->(@_);
}

sub _destringify {
    my ($self) = shift;
    return $self->{'_serialization_module'}->can('parse')->(@_);
}

#----------------------------------------------------------------------

#XXX De-duplicate TODO
sub _create_msg {
    my ($self, $name, @parts) = @_;

    my $mod = "Net::WAMP::Message::$name";
    Module::Load::load($mod) if !$mod->can('new');

    return $mod->new(@parts);
}

#----------------------------------------------------------------------

1;
