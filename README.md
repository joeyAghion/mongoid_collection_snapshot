Mongoid Collection Snapshot
===========================

Easy maintenance of collections of processed data in MongoDB with the Mongoid 3.x ODM.

Quick example:
--------------

Suppose that you have a Mongoid model called `Artwork`, stored
in a MongoDB collection called `artworks` and the underlying documents 
look something like:

    { name: 'Flowers', artist: 'Andy Warhol', price: 3000000 }

From time to time, your system runs a map/reduce job to compute the
average price of each artist's works, resulting in a collection called
`artist_average_price` that contains documents that look like:

    { _id: { artist: 'Andy Warhol'}, value: { price: 1500000 } }

If your system wants to maintain and use this average price data, it has 
to do so at the level of raw MongoDB operations, since
map/reduce result documents don't map well to models in Mongoid.
Furthermore, even though map/reduce jobs can take some time to run, you probably 
want the entire `artist_average_price` collection populated atomically
from the point of view of your system, since otherwise you don't ever
know the state of the data in the collection - you could access it in
the middle of a map/reduce and get partial, incorrect results.

mongoid_collection_snapshot solves this problem by providing an atomic
view of collections of data like map/reduce results that live outside
of Mongoid. 

In the example above, we'd set up our average artist price collection like:

``` ruby
class AverageArtistPrice
  include Mongoid::CollectionSnapshot

  def build
    map = <<-EOS
      function() {
        emit({artist: this['artist']}, {count: 1, sum: this['price']})
      }
    EOS

    reduce = <<-EOS
      function(key, values) {
        var sum = 0;
        var count = 0;
        values.forEach(function(value) {
          sum += value['price'];
          count += value['count'];
        });
        return({count: count, sum: sum});
      }
    EOS

    Mongoid.default_session.command(
      "mapreduce" => "artworks",
      map: map,
      reduce: reduce,
      out: collection_snapshot.name)
  end

  def average_price(artist)
    doc = collection_snapshot.find({'_id.artist': artist}).first
    doc['value']['sum']/doc['value']['count']
  end
end
```

Now, if you want
to schedule a recomputation, just call `AverageArtistPrice.create`. The latest
snapshot is always available as `AverageArtistPrice.latest`, so you can write
code like:

``` ruby
warhol_expected_price = AverageArtistPrice.latest.average_price('Andy Warhol')
```

And always be sure that you'll never be looking at partial results. The only
thing you need to do to hook into mongoid_collection_snapshot is implement the
method `build`, which populates the collection snapshot and any indexes you need.

By default, mongoid_collection_snapshot maintains the most recent two snapshots 
computed any given time.

Multi-collection snapshots
--------------------------

You can maintain multiple collections atomically within the same snapshot by
passing unique collection identifiers to ``collection_snaphot`` when you call it 
in your build or query methods:

``` ruby
class ArtistStats
  include Mongoid::CollectionSnapshot

  def build
    # ...
    # define map/reduce for average and max aggregations
    # ...
    Mongoid.default_session.command("mapreduce" => "artworks", map: map_avg, reduce: reduce_avg, out: collection_snapshot('average'))
    Mongoid.default_session.command("mapreduce" => "artworks", map: map_max, reduce: reduce_max, out: collection_snapshot('max'))
  end

  def average_price(artist)
    doc = collection_snapshot('average').find({'_id.artist': artist}).first
    doc['value']['sum']/doc['value']['count']
  end

  def max_price(artist)
    doc = collection_snapshot('max').find({'_id.artist': artist}).first
    doc['value']['max']
  end
end
```


Custom database connections
---------------------------

Your class can specify a custom database for storage of collection snapshots by overriding the `snapshot_session` instance method. In this example, we memoize the connection at the class level to avoid creating many separate connection instances.

```ruby
class FooStats
  include Mongoid::CollectionSnapshot

  def build
    # ...
  end

  def snapshot_session
    self.class.snapshot_session
  end

  def self.snapshot_session
    @@snapshot_session ||= Moped::Session.new(['127.0.0.1:27017']).tap do |s|
      s.use :alternative_db
    end
  end
end
```

License
=======

MIT License, see [LICENSE.txt](https://github.com/aaw/mongoid_collection_snapshot/blob/master/LICENSE.txt) for details.
