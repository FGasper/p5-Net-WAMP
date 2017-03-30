package IO::Framed::X::WriteError;

use strict;
use warnings;

use parent qw( IO::Framed::X::ErrnoBase );

sub _new {
    my ($class, $err) = @_;

    return $class->SUPER::_new( "Write error: $err", OS_ERROR => $err );
}

1;
