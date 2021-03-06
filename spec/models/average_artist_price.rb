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
          sum += value['sum'];
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
    doc = collection_snapshot.where({'_id.artist' => artist}).first
    doc['value']['sum']/doc['value']['count']
  end

end
