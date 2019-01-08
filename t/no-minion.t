use 5.010;
use Test::More;

use Mojo::File 'path';
use Mojo::Recache;

my $cache = Mojo::Recache->new(app => __PACKAGE__, home => path(__FILE__)->dirname);
$cache->file('fd4f16df902fda892dadf2dd1bf40742')->remove;
$cache->on(retrieved => sub { is pop, 'fd4f16df902fda892dadf2dd1bf40742', 'emitted right received name' });
$cache->on(stored => sub { is pop, 'fd4f16df902fda892dadf2dd1bf40742', 'emitted right stored name' });
is $cache->start, undef, 'start disabled due to minion disabled';
is $cache->enqueued, undef, 'enqueued disabled due to minion disabled';
is $cache->enqueue, undef, 'enqueue disabled due to minion disabled';
is $cache->use_options(abc => 123)->options->{abc}, 123, 'right temporary option';
is $cache->options->{abc}, undef, 'temporary option gone';
is $cache->merge_options(abc => 123)->options->{abc}, 123, 'right permanent option';
is $cache->options->{abc}, 123, 'permanent option remained';
my $name = $cache->name(abc => ());
is $name, 'fd4f16df902fda892dadf2dd1bf40742', 'right name';
is $cache->short($name), 'fd4f16', 'right short name';
my $file = $cache->file($name);
is $file->basename, 'fd4f16df902fda892dadf2dd1bf40742', 'right file';
my $t1 = time;
is abc(), 123, 'right no cache value';
my $t2 = time;
ok $t2 - $t1 > 1, 'no cache';
is $cache->abc, 123, 'right first cache value';
my $t3 = time;
ok $t3 - $t2 > 1, 'first cache';
is $cache->abc, 123, 'right second cache value';
my $t4 = time;
ok $t4 - $t3 == 0, 'second cache';
$file->remove;

sub abc {
  sleep 2;
  return 123
}

done_testing;
