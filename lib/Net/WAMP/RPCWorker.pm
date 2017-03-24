package Net::WAMP::RPCWorker;

use strict;
use warnings;

use Net::WAMP::Messages ();

sub new {
    my ($class, $callee, $msg) = @_;

    return bless { _callee => $callee, _msg => $msg }, $class;
}

sub yield {
    my ($self, $opts_hr, @payload) = @_;

    $self->_not_already_interrupted();

    return $self->{'_callee'}->send_YIELD(
        $self->{'_msg'}->get('Request'),
        $opts_hr,
        @payload,
    );
}

#use Type::Serialiser ();
#
#sub yield_progress {
#    my ($self, @payload) = @_;
#
#    if (!defined $self->{'_can_progress'}) {
#        $self->{'_can_progress'} = !!$msg->get('Options')->{'receive_progress'},
#    }
#
#    if ($self->{'_can_progress'}) {
#        die sprintf('INVOCATION (%s) cannot receive progressive YIELD!', $self->{'_msg'}->get('Request'));
#    }
#
#    return $self->{'_callee'}->send_yield(
#        $self->{'_msg'}->get('Request'),
#        { progress => $Types::Serialiser::true },
#        @payload,
#    );
#}

sub error {
    my ($self, $details_hr, $err_uri, @args) = @_;

    $self->_not_already_interrupted();

    return $self->{'_callee'}->send_ERROR(
        $self->{'_msg'}->get('Request'),
        $details_hr,
        $err_uri,
        @args,
    );
}

sub interrupt {
    my ($self, $msg) = @_;

    $self->_not_already_interrupted();

    $self->{'_interrupted'} = 1;

    if ($self->{'_on_interrupt'}) {
        $self->{'_on_interrupt'}->($msg);
    }

    return;
}

#----------------------------------------------------------------------

sub _not_already_interrupted {
    my ($self, $msg) = @_;

    #XXX
    die "ALREADY INTERRUPTED!!" if $self->{'_interrupted'};

    return;
}

1;
