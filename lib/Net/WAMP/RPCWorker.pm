package Net::WAMP::RPCWorker;

=encoding utf-8

=head1 NAME

Net::WAMP::RPCWorker

=head1 SYNOPSIS

    if ($worker->caller_can_receive_progress()) {
        $worker->yield_progress( {}, \@args, \%args_kw );
    }

    $worker->error( {}, 'wamp.error.invalid_argument', \@args, \%args_kw );

    $worker->yield( {}, \@args, \%args_kw );

=head1 DESCRIPTION

This object is a convenience for doing RPC calls.

=cut

use strict;
use warnings;

use Types::Serialiser ();

use Net::WAMP::Messages ();

sub new {
    my ($class, $callee, $msg) = @_;

    return bless { _callee => $callee, _msg => $msg }, $class;
}

sub caller_can_receive_progress {
    my ($self) = @_;

    return $self->{'_msg'}->caller_can_receive_progress();
}

sub yield_progress {
    my ($self, $opts_hr) = @_;

    if (!$self->caller_can_receive_progress()) {
        die "Caller didn’t indicate acceptance of progressive results!";
    }

    local $opts_hr->{'progress'} = $Types::Serialiser::true;

    return $self->yield($opts_hr, @_[ 2 .. $#_ ]);
}

sub yield {
    my ($self, $opts_hr, @payload) = @_;

    #$self->_not_already_interrupted();

    return $self->{'_callee'}->send_YIELD(
        $self->{'_msg'}->get('Request'),
        $opts_hr,
        @payload,
    );
}

sub error {
    my ($self, $details_hr, $err_uri, @args) = @_;

    #$self->_not_already_interrupted();

    return $self->{'_callee'}->send_ERROR(
        $self->{'_msg'}->get('Request'),
        $details_hr,
        $err_uri,
        @args,
    );
}

#sub interrupt {
#    my ($self, $msg) = @_;
#
#    $self->_not_already_interrupted();
#
#    $self->{'_interrupted'} = 1;
#
#    if ($self->{'_on_interrupt'}) {
#        $self->{'_on_interrupt'}->($msg);
#    }
#
#    return;
#}

#----------------------------------------------------------------------

#sub _not_already_interrupted {
#    my ($self, $msg) = @_;
#
#    #XXX
#    die "ALREADY INTERRUPTED!!" if $self->{'_interrupted'};
#
#    return;
#}

1;
