package Net::WAMP::SessionScope;

use strict;
use warnings;

sub _get_next_session_scope {
    my ($self) = @_;

    if (defined $self->{'_last_session_scope'}) {
        $self->{'_last_session_scope'}++;
    }
    else {
        $self->{'_last_session_scope'} = 0;
    }

    return $self->{'_last_session_scope'};
}

1;
