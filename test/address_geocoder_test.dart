// The geocoding cache behind the shipment map previews.
//
// What this starts from: the shipment tiles called the geocoder from inside
// `build()`, through `FutureBuilder(future: getCoordinatesFromAddress(...))`.
// A future built in `build` is rebuilt with the widget, so every provider
// notification and every tab switch started a fresh network lookup for every
// visible row. The requests queued and the app stalled more the longer it ran.

import 'dart:io';

import 'package:blockatie/utils/address_geocoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

String _source(String path) => File(path).readAsStringSync();

/// The file with its comments stripped, so a comment explaining a removed
/// pattern cannot satisfy a scan looking for that pattern.
String _code(String path) => _source(path)
    .split('\n')
    .where(
      (line) =>
          !line.trimLeft().startsWith('//') && !line.trimLeft().startsWith('*'),
    )
    .join('\n');

const _homeTile = 'lib/views/pages/home/components/order_tile.dart';
const _instantTile =
    'lib/views/pages/home/tabs/shipment-instant/components/order_tile.dart';
const _acceptTile =
    'lib/views/pages/home/tabs/shipment-instant/components/accept_order_tile.dart';
const _preview = 'lib/views/widgets/shipment_map_preview.dart';
const _filterPage = 'lib/views/pages/home/filter/filter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(AddressGeocoder.resetForTesting);
  tearDown(AddressGeocoder.resetForTesting);

  group('cache', () {
    test('1. an unresolved address reports nothing cached', () {
      expect(AddressGeocoder.cached('Amman, Jordan'), isNull);
    });

    test('2. a resolved address is served without another lookup', () async {
      const address = 'Al-Muttalib Ibn Rabeeah';
      const coordinates = LatLng(31.95, 35.91);
      AddressGeocoder.seedForTesting(address, coordinates);

      expect(AddressGeocoder.cached(address), coordinates);
      expect(await AddressGeocoder.resolve(address), coordinates);
    });

    test('3. the address key ignores surrounding whitespace', () {
      const coordinates = LatLng(31.95, 35.91);
      AddressGeocoder.seedForTesting('  Irbid  ', coordinates);

      expect(AddressGeocoder.cached('Irbid'), coordinates);
      expect(AddressGeocoder.cached('  Irbid'), coordinates);
    });

    test(
      '4. an empty address resolves to the fallback, not an error',
      () async {
        var calls = 0;
        AddressGeocoder.debugLookupOverride = (_) async {
          calls++;
          return const LatLng(1, 1);
        };

        expect(await AddressGeocoder.resolve(''), kFallbackLatLng);
        expect(await AddressGeocoder.resolve('   '), kFallbackLatLng);
        // An address with nothing in it is never worth a lookup.
        expect(calls, 0);
      },
    );

    test('5. a failed lookup falls back instead of throwing', () async {
      AddressGeocoder.debugLookupOverride =
          (_) async => throw Exception('geocoder unavailable');

      expect(await AddressGeocoder.resolve('Nowhere At All'), kFallbackLatLng);
    });

    test('6. concurrent callers share one lookup', () async {
      const address = 'Shared Street';
      var calls = 0;
      AddressGeocoder.debugLookupOverride = (_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return const LatLng(32.1, 35.2);
      };

      // Three rows showing the same address, all asking at the same time.
      final results = await Future.wait([
        AddressGeocoder.resolve(address),
        AddressGeocoder.resolve(address),
        AddressGeocoder.resolve(address),
      ]);

      expect(results, everyElement(const LatLng(32.1, 35.2)));
      expect(calls, 1);
    });

    test('7. a resolved address is never looked up again', () async {
      const address = 'Reused Street';
      var calls = 0;
      AddressGeocoder.debugLookupOverride = (_) async {
        calls++;
        return const LatLng(31.0, 35.0);
      };

      await AddressGeocoder.resolve(address);
      await AddressGeocoder.resolve(address);
      await AddressGeocoder.resolve('  $address  ');

      expect(calls, 1);
      expect(AddressGeocoder.cached(address), const LatLng(31.0, 35.0));
    });
  });

  group('call sites', () {
    test('8. no tile builds its geocoding future inside build()', () {
      for (final tile in [_homeTile, _instantTile]) {
        expect(
          _code(tile).contains('future: getCoordinatesFromAddress('),
          isFalse,
          reason: tile,
        );
      }
    });

    test('9. both tiles resolve once and re-resolve only on change', () {
      for (final tile in [_homeTile, _instantTile]) {
        final source = _code(tile);
        expect(
          source.contains('AddressGeocoder.resolve('),
          isTrue,
          reason: tile,
        );
        expect(source.contains('didUpdateWidget'), isTrue, reason: tile);
        expect(
          source.contains('oldWidget.clientLocation != widget.clientLocation'),
          isTrue,
          reason: tile,
        );
      }
    });

    test('10. a known address paints without a spinner', () {
      for (final tile in [_homeTile, _instantTile]) {
        expect(
          _code(tile).contains('initialData: AddressGeocoder.cached('),
          isTrue,
          reason: tile,
        );
      }
    });

    test('11. no list row builds a full interactive GoogleMap', () {
      for (final tile in [_homeTile, _instantTile, _acceptTile]) {
        expect(_code(tile).contains('GoogleMap('), isFalse, reason: tile);
        expect(
          _code(tile).contains('ShipmentMapPreview('),
          isTrue,
          reason: tile,
        );
      }
    });

    test('12. the row preview is a lite, non-interactive map', () {
      final source = _code(_preview);
      expect(source.contains('liteModeEnabled: true'), isTrue);
      expect(source.contains('scrollGesturesEnabled: false'), isTrue);
      expect(source.contains('zoomGesturesEnabled: false'), isTrue);
    });

    test('13. a tile without a status name does not throw', () {
      // `widget.statusNameEn!.toLowerCase()` ran while building the row.
      expect(_code(_homeTile).contains('statusNameEn!'), isFalse);
    });

    test('14. filter results are built lazily', () {
      final source = _code(_filterPage);
      expect(source.contains('SliverList.builder'), isTrue);
      expect(source.contains('NeverScrollableScrollPhysics'), isFalse);
      expect(source.contains('shrinkWrap: true'), isFalse);
    });
  });
}
