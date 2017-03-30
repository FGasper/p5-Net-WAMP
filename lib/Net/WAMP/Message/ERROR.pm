package Net::WAMP::Message::ERROR;

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Type  Request  Metadata  Error  Arguments  ArgumentsKw );

1;
