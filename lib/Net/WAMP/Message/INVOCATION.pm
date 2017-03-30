package Net::WAMP::Message::INVOCATION;

use parent qw( Net::WAMP::Base::SessionMessage );

use constant PARTS => qw( Request  Registration  Metadata  Arguments  ArgumentsKw );

1;
