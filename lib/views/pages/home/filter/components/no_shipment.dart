// no_shipment_screen.dart
import 'package:blockatie/provider/filter.dart';
import 'package:blockatie/views/pages/home/filter/filter.dart';
import 'package:blockatie/views/widgets/cutom-appbar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NoShipmentScreen extends StatelessWidget {
  const NoShipmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2), // light grey background
      appBar: CustomAppBar(
        title: 'Filter',
        subtitle: 'Filter by date, shipment status, location, or name',
        showBtn: false,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "No shipments found",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () {
                // Clear filters and go back to filter screen
                Provider.of<FilterProvider>(
                  context,
                  listen: false,
                ).resetFilters();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const FilterPage()),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3E4DB0),
                side: const BorderSide(color: Color(0xFF3E4DB0)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text("Clear Filters"),
            ),
          ],
        ),
      ),
    );
  }
}
