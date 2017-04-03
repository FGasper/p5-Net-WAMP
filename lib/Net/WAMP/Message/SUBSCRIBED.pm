package Net::WAMP::Message::SUBSCRIBED;

use strict;
use warnings;

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Request  Subscription );

1;
