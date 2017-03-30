package Net::WAMP::Message::EVENT;

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Subscription  Publication  Metadata  Arguments  ArgumentsKw );

1;
