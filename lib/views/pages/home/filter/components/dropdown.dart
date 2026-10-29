// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:blockatie/provider/filter.dart';

// class ClientDropdownWidget extends StatelessWidget {
//   const ClientDropdownWidget({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return Consumer<FilterProvider>(
//       builder: (context, filterProvider, child) {
//         return Container(
//           decoration: BoxDecoration(
//             border: Border.all(color: Colors.grey.shade300),
//             borderRadius: BorderRadius.circular(8),
//           ),
//           child: DropdownButtonFormField<String>(
//             value: filterProvider.selectedClientName,
//             hint: Row(
//               children: [
//                 Icon(Icons.person_outline, color: Colors.grey.shade600),
//                 const SizedBox(width: 12),
//                 const Text(
//                   "Name of the Customer",
//                   style: TextStyle(color: Colors.grey),
//                 ),
//               ],
//             ),
//             decoration: const InputDecoration(
//               border: InputBorder.none,
//               contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
//             ),
//             items: filterProvider.isLoadingClients
//                 ? []
//                 : filterProvider.clientsMap.keys.map((String clientName) {
//                     return DropdownMenuItem<String>(
//                       value: clientName,
//                       child: Text(
//                         clientName,
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                     );
//                   }).toList(),
//             onChanged: filterProvider.isLoadingClients
//                 ? null
//                 : (String? newValue) {
//                     filterProvider.setSelectedClient(newValue);
//                   },
//             onTap: () async {
//               // Load clients when dropdown is tapped
//               await filterProvider.loadClients();
//             },
//             icon: filterProvider.isLoadingClients
//                 ? const SizedBox(
//                     width: 20,
//                     height: 20,
//                     child: CircularProgressIndicator(strokeWidth: 2),
//                   )
//                 : const Icon(Icons.expand_more),
//           ),
//         );
//       },
//     );
//   }
// }
