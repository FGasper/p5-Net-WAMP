package Net::WAMP::Message::CALL;

use parent qw( Net::WAMP::SessionMessage );

use constant PARTS => qw( Request  Options  Procedure  Arguments  ArgumentsKw );

1;
