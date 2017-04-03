package Net::WAMP::Message::PUBLISH;

use strict;
use warnings;

use parent qw( Net::WAMP::Base::SessionMessage );

use Types::Serialiser ();

use constant PARTS => qw( Request  Metadata  Topic  Arguments  ArgumentsKw );

sub publisher_wants_acknowledgement {
    return Types::Serialiser::is_true( $_[0]->get('Metadata')->{'acknowledge'} );
}

sub publisher_wants_to_be_excluded {
    return !Types::Serialiser::is_false( $_[0]->get('Metadata')->{'exclude_me'} );
}

1;
