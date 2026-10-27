class Channel {
  const Channel({
    required this.name,
    required this.url,
    this.tvgId,
    this.tvgName,
    this.logo,
    this.group,
    this.number,
  });

  final String name;
  final String url;
  final String? tvgId;
  final String? tvgName;
  final String? logo;
  final String? group;

  /// tvg-chno。無ければ読み込み順で採番される。
  final int? number;

  Channel withNumber(int n) => Channel(
        name: name,
        url: url,
        tvgId: tvgId,
        tvgName: tvgName,
        logo: logo,
        group: group,
        number: n,
      );
}

class Programme {
  const Programme({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.description,
    this.category,
  });

  final String channelId;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String? description;
  final String? category;

  bool isOnAir(DateTime now) => !now.isBefore(start) && now.isBefore(stop);
}
