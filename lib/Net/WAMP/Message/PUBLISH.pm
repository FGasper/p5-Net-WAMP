package Net::WAMP::Message::PUBLISH;

use parent qw( Net::WAMP::SessionMessage );

use constant PARTS => qw( Request  Options  Topic  Arguments  ArgumentsKw );

1;
