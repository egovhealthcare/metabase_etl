# CARE FDW Table Catalog

This catalog was prepared from the current files under `care/emr/models/` and
`care/facility/models/` only. Legacy tables that exist only in migrations are
not included.

## Facility

| Table | Model | Default |
|---|---|---|
| `facility_facility` | `care/facility/models/facility.py::Facility` | daily full |
| `facility_facilityflag` | `care/facility/models/facility_flag.py::FacilityFlag` | daily full |
| `facility_patientmobileotp` | `care/facility/models/patient.py::PatientMobileOTP` | excluded |

## Core Dimensions

| Table | Model | Default |
|---|---|---|
| `emr_organization` | `care/emr/models/organization.py::Organization` | daily full |
| `emr_facilityorganization` | `care/emr/models/organization.py::FacilityOrganization` | daily full |
| `emr_organizationuser` | `care/emr/models/organization.py::OrganizationUser` | daily incremental |
| `emr_facilityorganizationuser` | `care/emr/models/organization.py::FacilityOrganizationUser` | daily incremental |
| `emr_facilitylocation` | `care/emr/models/location.py::FacilityLocation` | hourly incremental |
| `emr_facilitylocationorganization` | `care/emr/models/location.py::FacilityLocationOrganization` | daily incremental |
| `emr_facilitylocationencounter` | `care/emr/models/location.py::FacilityLocationEncounter` | hourly incremental |

## Patient And Encounter

| Table | Model | Default |
|---|---|---|
| `emr_patient` | `care/emr/models/patient.py::Patient` | hourly incremental |
| `emr_patientorganization` | `care/emr/models/patient.py::PatientOrganization` | hourly incremental |
| `emr_patientuser` | `care/emr/models/patient.py::PatientUser` | hourly incremental |
| `emr_patientidentifierconfig` | `care/emr/models/patient.py::PatientIdentifierConfig` | daily full |
| `emr_patientidentifier` | `care/emr/models/patient.py::PatientIdentifier` | hourly incremental |
| `emr_encounter` | `care/emr/models/encounter.py::Encounter` | hourly incremental |
| `emr_encounterorganization` | `care/emr/models/encounter.py::EncounterOrganization` | hourly incremental |

## Clinical

| Table | Model | Default |
|---|---|---|
| `emr_condition` | `care/emr/models/condition.py::Condition` | hourly incremental |
| `emr_allergyintolerance` | `care/emr/models/allergy_intolerance.py::AllergyIntolerance` | hourly incremental |
| `emr_observation` | `care/emr/models/observation.py::Observation` | hourly incremental |
| `emr_diagnosticreport` | `care/emr/models/diagnostic_report.py::DiagnosticReport` | hourly incremental |
| `emr_servicerequest` | `care/emr/models/service_request.py::ServiceRequest` | hourly incremental |
| `emr_specimen` | `care/emr/models/specimen.py::Specimen` | hourly incremental |
| `emr_consent` | `care/emr/models/consent.py::Consent` | hourly incremental |

## Medication

| Table | Model | Default |
|---|---|---|
| `emr_medicationrequestprescription` | `care/emr/models/medication_request.py::MedicationRequestPrescription` | hourly incremental |
| `emr_medicationrequest` | `care/emr/models/medication_request.py::MedicationRequest` | hourly incremental |
| `emr_medicationstatement` | `care/emr/models/medication_statement.py::MedicationStatement` | hourly incremental |
| `emr_medicationadministration` | `care/emr/models/medication_administration.py::MedicationAdministration` | hourly incremental |
| `emr_medicationdispense` | `care/emr/models/medication_dispense.py::MedicationDispense` | hourly incremental |
| `emr_dispenseorder` | `care/emr/models/medication_dispense.py::DispenseOrder` | hourly incremental |

## Billing

| Table | Model | Default |
|---|---|---|
| `emr_account` | `care/emr/models/account.py::Account` | hourly incremental |
| `emr_chargeitem` | `care/emr/models/charge_item.py::ChargeItem` | hourly incremental |
| `emr_invoice` | `care/emr/models/invoice.py::Invoice` | hourly incremental |
| `emr_paymentreconciliation` | `care/emr/models/payment_reconciliation.py::PaymentReconciliation` | hourly incremental |
| `emr_facilitymonetoryconfig` | `care/emr/models/facility_config.py::FacilityMonetoryConfig` | daily full |

## Definitions And Config

| Table | Model | Default |
|---|---|---|
| `emr_activitydefinition` | `care/emr/models/activity_definition.py::ActivityDefinition` | daily full |
| `emr_observationdefinition` | `care/emr/models/observation_definition.py::ObservationDefinition` | daily full |
| `emr_chargeitemdefinition` | `care/emr/models/charge_item_definition.py::ChargeItemDefinition` | daily full |
| `emr_resourcecategory` | `care/emr/models/resource_category.py::ResourceCategory` | daily full |
| `emr_healthcareservice` | `care/emr/models/healthcare_service.py::HealthcareService` | daily full |
| `emr_valueset` | `care/emr/models/valueset.py::ValueSet` | daily full |
| `emr_tagconfig` | `care/emr/models/tag_config.py::TagConfig` | daily full |
| `emr_specimendefinition` | `care/emr/models/specimen_definition.py::SpecimenDefinition` | daily full |

## Inventory And Supply

| Table | Model | Default |
|---|---|---|
| `emr_productknowledge` | `care/emr/models/product_knowledge.py::ProductKnowledge` | daily full |
| `emr_product` | `care/emr/models/product.py::Product` | daily incremental |
| `emr_inventoryitem` | `care/emr/models/inventory_item.py::InventoryItem` | hourly incremental |
| `emr_supplyrequest` | `care/emr/models/supply_request.py::SupplyRequest` | hourly incremental |
| `emr_requestorder` | `care/emr/models/supply_request.py::RequestOrder` | hourly incremental |
| `emr_supplydelivery` | `care/emr/models/supply_delivery.py::SupplyDelivery` | hourly incremental |
| `emr_deliveryorder` | `care/emr/models/supply_delivery.py::DeliveryOrder` | hourly incremental |

## Scheduling

| Table | Model | Default |
|---|---|---|
| `emr_schedulableresource` | `care/emr/models/scheduling/schedule.py::SchedulableResource` | daily full |
| `emr_schedule` | `care/emr/models/scheduling/schedule.py::Schedule` | daily incremental |
| `emr_availability` | `care/emr/models/scheduling/schedule.py::Availability` | daily incremental |
| `emr_availabilityexception` | `care/emr/models/scheduling/schedule.py::AvailabilityException` | daily incremental |
| `emr_tokenslot` | `care/emr/models/scheduling/booking.py::TokenSlot` | hourly incremental |
| `emr_tokenbooking` | `care/emr/models/scheduling/booking.py::TokenBooking` | hourly incremental |
| `emr_tokenqueue` | `care/emr/models/scheduling/token.py::TokenQueue` | daily full |
| `emr_tokensubqueue` | `care/emr/models/scheduling/token.py::TokenSubQueue` | daily full |
| `emr_tokencategory` | `care/emr/models/scheduling/token.py::TokenCategory` | daily full |
| `emr_token` | `care/emr/models/scheduling/token.py::Token` | hourly incremental |

## Questionnaires, Notes, Reports, Misc

| Table | Model | Default |
|---|---|---|
| `emr_questionnairetag` | `care/emr/models/questionnaire.py::QuestionnaireTag` | daily full |
| `emr_questionnaire` | `care/emr/models/questionnaire.py::Questionnaire` | daily full |
| `emr_questionnaireorganization` | `care/emr/models/questionnaire.py::QuestionnaireOrganization` | daily full |
| `emr_questionnairefacilityorganization` | `care/emr/models/questionnaire.py::QuestionnaireFacilityOrganization` | daily full |
| `emr_questionnaireresponsetemplate` | `care/emr/models/questionnaire.py::QuestionnaireResponseTemplate` | daily full |
| `emr_formsubmission` | `care/emr/models/questionnaire.py::FormSubmission` | hourly incremental |
| `emr_questionnaireresponse` | `care/emr/models/questionnaire.py::QuestionnaireResponse` | hourly incremental |
| `emr_template` | `care/emr/models/report/template.py::Template` | daily full |
| `emr_reportupload` | `care/emr/models/report/report_upload.py::ReportUpload` | hourly incremental |
| `emr_fileupload` | `care/emr/models/file_upload.py::FileUpload` | hourly incremental |
| `emr_notethread` | `care/emr/models/notes.py::NoteThread` | hourly incremental |
| `emr_notemessage` | `care/emr/models/notes.py::NoteMessage` | hourly incremental |
| `emr_metaartifact` | `care/emr/models/meta_artifact.py::MetaArtifact` | daily incremental |
| `emr_userresourcefavorites` | `care/emr/models/favorites.py::UserResourceFavorites` | daily incremental |
| `emr_uservaluesetpreference` | `care/emr/models/valueset.py::UserValueSetPreference` | daily incremental |

## Device And Resource Requests

| Table | Model | Default |
|---|---|---|
| `emr_device` | `care/emr/models/device.py::Device` | hourly incremental |
| `emr_deviceencounterhistory` | `care/emr/models/device.py::DeviceEncounterHistory` | hourly incremental |
| `emr_devicelocationhistory` | `care/emr/models/device.py::DeviceLocationHistory` | hourly incremental |
| `emr_deviceservicehistory` | `care/emr/models/device.py::DeviceServiceHistory` | hourly incremental |
| `emr_resourcerequest` | `care/emr/models/resource_request.py::ResourceRequest` | hourly incremental |
| `emr_resourcerequestcomment` | `care/emr/models/resource_request.py::ResourceRequestComment` | hourly incremental |

