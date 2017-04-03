package Net::WAMP::Message::INVOCATION;

use strict;
use warnings;

use parent qw( Net::WAMP::Base::SessionMessage );

use Types::Serialiser ();

use constant PARTS => qw( Request  Registration  Metadata  Arguments  ArgumentsKw );

use constant NUMERIC => qw( Request Registration );

sub caller_can_receive_progress {
    return Types::Serialiser::is_true( $_[0]->get('Metadata')->{'receive_progress'} );
}

1;
