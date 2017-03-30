package Net::WAMP::Message::AUTHENTICATE;

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Signature  Extra );

1;
