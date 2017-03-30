package IO::Framed::X::ErrnoBase;

use strict;
use warnings;

use parent qw( IO::Framed::X::Base );

sub errno_is {
    my ($self, $name) = @_;

    local $! = $self->get('OS_ERROR');
    return $!{$name};
}

1;
