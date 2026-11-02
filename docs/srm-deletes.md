# Handling deletes in the orcavault

Deletes are modelled as passing through the raw vault, and being closed in an effectivity
satellite in the business vault. The primary example of this currently is the SRM.

The warehouse handles deletes of the sequence run manager's library
associations. This allows data to be cleared if it is malformed upstream, and the
warehouse will capture it. The warehouse tracks these deletes for the SRM, and keeps
the history.

This is how it's implemented:

| Layer          | What happens to a delete                                                                                                                                                                                                                                                                                                                                                                    |
|----------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Staging        | `int_cdc_srm_libraryassociation` gives a delete the `library_id` and `sequence_id` of the row before it, using `cdc_fill_delete`. A value the delete already has is kept.                                                                                                                                                                                                                   |
| Raw vault      | `hub_library` loads the libraries of the sequence run manager, so the library of every association is in the hub. Hubs and links don't change with deletes, so the link keeps a delete association. `sat_library_sequencing_run_srm` records the delete like DMS using the link of the association it deleted.                                                                              |
| Business vault | `effsat_library_sequencing_run` keeps a link effective while it has at least one association, as a library can be on two sequences with the same instrument run. It closes the link when its last association is deleted, and starts it again if one is created again. A link from a legacy source, or from the sequence run manager without any rows in the satellite is always effective. |
| Marts          | `lims` reads the current links through `effsat_library_sequencing_run`. `em_library_services` leaves out deleted associations.                                                                                                                                                                                                                                                              |

A complication to this setup is that DMS writes a delete in an OrcaBus database as a
CDC row with `op = 'D'`, and only holds the primary key, e.g. `orcabus_id`. This means that
the orcavault needs to look back a row to find the previously created row data. If upstream
changes to replica identity full, this design can be simplified.

The deletes of other OrcaBus tables aren't handled yet, including a delete of a
sequence. When one is needed, it can follow a similar pattern.
