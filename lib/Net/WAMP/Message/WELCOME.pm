package Net::WAMP::Message::WELCOME;

use strict;
use warnings;

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Session  Metadata );

use constant NUMERIC => qw( Session );

1;
