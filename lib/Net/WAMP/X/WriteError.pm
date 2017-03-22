package Net::WAMP::X::WriteError;

use strict;
use warnings;

use parent qw( Net::WAMP::X::Base );

sub _new {
    my ($class, $err) = @_;

    return $class->SUPER::_new( "Write error: $err", OS_ERROR => $err );
}

sub errno_is {
    my ($self, $name) = @_;

    local $! = $self->get('OS_ERROR');
    return $!{$name};
}

1;
