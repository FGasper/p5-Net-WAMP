package Net::WAMP::Message::EVENT;

use parent qw( Net::WAMP::Message );

use constant PARTS => qw( Subscription  Publication  Details  Arguments  ArgumentsKw );

1;
