package Net::WAMP::Message::EVENT;

use strict;
use warnings;

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Subscription  Publication  Metadata  Arguments  ArgumentsKw );

1;
