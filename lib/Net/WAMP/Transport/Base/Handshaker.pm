package Net::WAMP::Transport::Base::Handshaker;

use strict;
use warnings;

sub did_handshake {
    my ($self) = @_;

    return $self->{'_handshake_done'} ? 1 : 0;
}

sub _set_handshake_done {
    shift()->{'_handshake_done'} = 1;

    return;
}

sub _verify_handshake_not_done {
    my ($self) = @_;

    die "Already did handshake!" if $self->{'_handshake_done'};

    return;
}

1;
