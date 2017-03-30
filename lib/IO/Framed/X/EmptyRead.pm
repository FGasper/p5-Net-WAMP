package IO::Framed::X::EmptyRead;

use strict;
use warnings;

use parent qw( IO::Framed::X::Base );

sub _new {
    my ($class) = @_;

    return $class->SUPER::_new( 'Got empty read; EOF?' );
}

1;
