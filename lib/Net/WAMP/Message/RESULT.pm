package Net::WAMP::Message::RESULT;

use strict;
use warnings;

use parent qw( Net::WAMP::Base::Message );

use Types::Serialiser ();

use constant PARTS => qw( Request  Metadata  Arguments  ArgumentsKw );

sub is_progress {
    return Types::Serialiser::is_true( $_[0]->get('Metadata')->{'progress'} );
}

use constant NUMERIC => qw( Request );

1;
