package Net::WAMP::Message::YIELD;

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Request  Metadata  Arguments  ArgumentsKw );

1;
