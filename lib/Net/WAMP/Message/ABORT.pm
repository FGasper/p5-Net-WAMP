package Net::WAMP::Message::ABORT;

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Metadata  Reason );

1;
