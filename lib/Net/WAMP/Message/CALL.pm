package Net::WAMP::Message::CALL;

use parent qw( Net::WAMP::Base::SessionMessage );

use constant PARTS => qw( Request  Metadata  Procedure  Arguments  ArgumentsKw );

1;
