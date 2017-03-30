package Net::WAMP::Message::RESULT;

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Request  Metadata  Arguments  ArgumentsKw );

1;
