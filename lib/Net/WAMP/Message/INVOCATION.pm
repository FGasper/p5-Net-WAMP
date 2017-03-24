package Net::WAMP::Message::INVOCATION;

use parent qw( Net::WAMP::SessionMessage );

use constant PARTS => qw( Request  Registration  Details  Arguments  ArgumentsKw );

1;
