#!/bin/bash
#
# IN THIS FILE
#
# Flush the DB from non-configuration data

ESQUUEL="
SET FOREIGN_KEY_CHECKS=0;

--MariaDB [koha]> SHOW TABLES;

--TRUNCATE account_credit_types;
--TRUNCATE account_credit_types_branches;
--TRUNCATE account_debit_types;
--TRUNCATE account_debit_types_branches;
--TRUNCATE account_offset_types;
--TRUNCATE account_offsets;
TRUNCATE accountlines;
TRUNCATE action_logs;
--TRUNCATE additional_field_values;
TRUNCATE additional_fields;
--TRUNCATE advanced_editor_macros;
--TRUNCATE alert;
TRUNCATE api_keys;
TRUNCATE aqbasket;
TRUNCATE aqbasketgroups;
TRUNCATE aqbasketusers;
TRUNCATE aqbooksellers;
--TRUNCATE aqbudgetborrowers;
--TRUNCATE aqbudgetperiods;
--TRUNCATE aqbudgets;
--TRUNCATE aqbudgets_planning;
--TRUNCATE aqcontacts;
--TRUNCATE aqcontract;
--TRUNCATE aqinvoice_adjustments;
--TRUNCATE aqinvoices;
--TRUNCATE aqorder_users;
--TRUNCATE aqorders;
--TRUNCATE aqorders_claims;
--TRUNCATE aqorders_items;
--TRUNCATE aqorders_transfers;
TRUNCATE article_requests;
--TRUNCATE audio_alerts;
TRUNCATE auth_header;
--TRUNCATE auth_subfield_structure;
--TRUNCATE auth_tag_structure;
--TRUNCATE auth_types;
--TRUNCATE authorised_value_categories;
--TRUNCATE authorised_values;
--TRUNCATE authorised_values_branches;
--TRUNCATE background_jobs;
TRUNCATE biblio;
--TRUNCATE biblio_framework;
TRUNCATE biblio_metadata;
TRUNCATE biblioitems;
--TRUNCATE borrower_attribute_types;
--TRUNCATE borrower_attribute_types_branches;
TRUNCATE borrower_attributes;
TRUNCATE borrower_debarments;
TRUNCATE borrower_files;
DELETE FROM borrower_message_preferences WHERE borrowernumber IS NOT NULL; --Defaults are with NULL
--TRUNCATE borrower_message_transport_preferences; --Relevant parts are already ON CASCADE DELETE:d from the parent table
TRUNCATE borrower_modifications;
TRUNCATE borrower_password_recovery;
TRUNCATE borrower_relationships;
TRUNCATE borrowers;
--TRUNCATE branch_transfer_limits;
--TRUNCATE branches;
--TRUNCATE branches_overdrive;
TRUNCATE branchtransfers;
TRUNCATE browser;
TRUNCATE cash_register_actions;
--TRUNCATE cash_registers;
--TRUNCATE categories;
--TRUNCATE categories_branches;
--TRUNCATE circulation_rules;
--TRUNCATE cities;
--TRUNCATE class_sort_rules;
--TRUNCATE class_sources;
--TRUNCATE class_split_rules;
--TRUNCATE club_enrollment_fields;
TRUNCATE club_enrollments;
--TRUNCATE club_fields;
TRUNCATE club_holds;
TRUNCATE club_holds_to_patron_holds;
--TRUNCATE club_template_enrollment_fields;
--TRUNCATE club_template_fields;
--TRUNCATE club_templates;
--TRUNCATE clubs;
TRUNCATE collections;
TRUNCATE collections_tracking;
--TRUNCATE columns_settings;
TRUNCATE course_instructors;
TRUNCATE course_items;
TRUNCATE course_reserves;
--TRUNCATE courses;
TRUNCATE cover_images;
--TRUNCATE creator_batches;
--TRUNCATE creator_images;
--TRUNCATE creator_layouts;
--TRUNCATE creator_templates;
--TRUNCATE currency;
TRUNCATE deletedbiblio;
TRUNCATE deletedbiblio_metadata;
TRUNCATE deletedbiblioitems;
TRUNCATE deletedborrowers;
TRUNCATE deleteditems;
--TRUNCATE desks;
TRUNCATE discharges;
TRUNCATE edifact_ean;
TRUNCATE edifact_messages;
--TRUNCATE export_format;
TRUNCATE hold_fill_targets;
--TRUNCATE housebound_profile;
--TRUNCATE housebound_role;
--TRUNCATE housebound_visit;
TRUNCATE illcomments;
TRUNCATE illrequestattributes;
TRUNCATE illrequests;
TRUNCATE import_auths;
TRUNCATE import_batch_profiles;
TRUNCATE import_batches;
TRUNCATE import_biblios;
TRUNCATE import_items;
TRUNCATE import_record_matches;
TRUNCATE import_records;
TRUNCATE issues;
--TRUNCATE item_circulation_alert_preferences;
TRUNCATE items;
TRUNCATE items_last_borrower;
--TRUNCATE items_search_fields;
--TRUNCATE itemtypes;
--TRUNCATE itemtypes_branches;
--TRUNCATE keyboard_shortcuts;
--TRUNCATE language_descriptions;
--TRUNCATE language_rfc4646_to_iso639;
--TRUNCATE language_script_bidi;
--TRUNCATE language_script_mapping;
--TRUNCATE language_subtag_registry;
--TRUNCATE letter;
--TRUNCATE library_groups;
--TRUNCATE library_smtp_servers;
--TRUNCATE linktracker;
--TRUNCATE localization;
--TRUNCATE marc_matchers;
--TRUNCATE marc_modification_template_actions;
--TRUNCATE marc_modification_templates;
--TRUNCATE marc_subfield_structure;
--TRUNCATE marc_tag_structure;
--TRUNCATE matchchecks;
--TRUNCATE matcher_matchpoints;
--TRUNCATE matchpoint_component_norms;
--TRUNCATE matchpoint_components;
--TRUNCATE matchpoints;
--TRUNCATE message_attributes;
TRUNCATE message_queue;
--TRUNCATE message_transport_types;
--TRUNCATE message_transports;
TRUNCATE messages;
--TRUNCATE misc_files;
TRUNCATE need_merge_authorities;
--TRUNCATE oai_sets;
--TRUNCATE oai_sets_biblios;
--TRUNCATE oai_sets_descriptions;
--TRUNCATE oai_sets_mappings;
TRUNCATE oauth_access_tokens;
TRUNCATE old_issues;
TRUNCATE old_reserves;
--TRUNCATE opac_news;
--TRUNCATE overduerules;
--TRUNCATE overduerules_transport_types;
TRUNCATE patron_consent;
TRUNCATE patron_list_patrons;
TRUNCATE patron_lists;
TRUNCATE patronimage;
TRUNCATE pending_offline_operations;
--TRUNCATE permissions;
--TRUNCATE plugin_data;
--TRUNCATE plugin_methods;
--TRUNCATE printers_profile;
--TRUNCATE problem_reports;
TRUNCATE pseudonymized_borrower_attributes;
TRUNCATE pseudonymized_transactions;
--TRUNCATE quotes;
--TRUNCATE ratings;
--TRUNCATE repeatable_holidays;
--TRUNCATE reports_dictionary;
TRUNCATE reserves;
TRUNCATE return_claims;
--TRUNCATE reviews;
--TRUNCATE saved_reports;
--TRUNCATE saved_sql;
--TRUNCATE search_field;
TRUNCATE search_history;
--TRUNCATE search_marc_map;
--TRUNCATE search_marc_to_field;
TRUNCATE serial;
TRUNCATE serialitems;
TRUNCATE sessions;
--TRUNCATE sms_providers;
--TRUNCATE smtp_servers;
--TRUNCATE social_data;
--TRUNCATE special_holidays;
TRUNCATE statistics;
TRUNCATE stockrotationitems;
TRUNCATE stockrotationrotas;
TRUNCATE stockrotationstages;
TRUNCATE subscription;
--TRUNCATE subscription_frequencies;
--TRUNCATE subscription_numberpatterns;
TRUNCATE subscriptionhistory;
TRUNCATE subscriptionroutinglist;
TRUNCATE suggestions;
--TRUNCATE systempreferences;
--TRUNCATE tables_settings;
TRUNCATE tags;
TRUNCATE tags_all;
TRUNCATE tags_approval;
TRUNCATE tags_index;
TRUNCATE tmp_holdsqueue;
--TRUNCATE transport_cost;
TRUNCATE uploaded_files;
TRUNCATE user_permissions;
--TRUNCATE userflags;
--TRUNCATE vendor_edi_accounts;
--TRUNCATE virtualshelfcontents;
--TRUNCATE virtualshelfshares;
--TRUNCATE virtualshelves;
--TRUNCATE z3950servers;
TRUNCATE zebraqueue;

"



#Empty all previously migrated data, except configurations. You don't want this when merging records :)
echo "$ESQUUEL" | mysql --user="$KOHA_DB_USER" --password="$KOHA_DB_PASS" "$KOHA_DB"

