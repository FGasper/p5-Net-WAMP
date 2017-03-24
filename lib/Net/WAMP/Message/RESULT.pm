package Net::WAMP::Message::RESULT;

use parent qw( Net::WAMP::Message );

use constant PARTS => qw( Request  Details  Arguments  ArgumentsKw );

1;
