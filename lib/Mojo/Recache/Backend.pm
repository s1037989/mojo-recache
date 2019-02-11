package Mojo::Recache::Backend;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';

has 'recache' => sub { die }, weak => 1;

sub retrieve { croak 'Method "retrieve" not implemented by subclass' }

sub store    { croak 'Method "store" not implemented by subclass' }

1;
