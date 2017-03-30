package Net::WAMP::Message::PUBLISH;

use parent qw( Net::WAMP::Base::SessionMessage );

use constant PARTS => qw( Request  Metadata  Topic  Arguments  ArgumentsKw );

1;
