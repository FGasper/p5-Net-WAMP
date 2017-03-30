package IO::Framed::X::ReadError;

use strict;
use warnings;

use parent qw( IO::Framed::X::ErrnoBase );

sub _new {
    my ($class, $err) = @_;

    return $class->SUPER::_new( "Read error: $err", OS_ERROR => $err );
}

1;
