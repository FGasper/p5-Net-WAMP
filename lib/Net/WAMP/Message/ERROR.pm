package Net::WAMP::Message::ERROR;

use parent qw( Net::WAMP::Message );

use constant PARTS => qw( Type  Request  Details  Error  Arguments  ArgumentsKw );

1;
