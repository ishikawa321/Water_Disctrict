# Implemented relational model

This reflects InitialScope, Phase2Concerns and the current model snapshot, not an unverified Midterm ERD. UUID primary keys are internal; ordinary UI flows show references and string account numbers. Role has an integer key. Join entities use composite keys. All foreign keys use Restrict deletion.

```mermaid
erDiagram
    User ||--o{ UserRole : holds
    Role ||--o{ UserRole : grants
    Role ||--o{ RolePermission : contains
    User ||--o| AccountOwnership : owns
    CustomerAccount ||--o{ AccountOwnership : linked
    CustomerAccount ||--o{ ServiceConcern : receives
    User ||--o{ ServiceConcern : records
    ServiceConcern ||--o{ ConcernEvent : preserves
    User ||--o{ ConcernEvent : acts
    ServiceConcern ||--o| RepairTicket : generates
    RepairTicket ||--o{ TicketEvent : preserves
    User ||--o{ TicketEvent : acts
    PlumberResource o|--o{ RepairTicket : assigned
    PlumberResource o|--o{ TicketEvent : assignment_history
    User ||--o{ AuditRecord : acts
    User {
        uuid Id PK
        string Username UK
        string PasswordHash
        string DisplayName
        bool Active
    }
    CustomerAccount {
        uuid Id PK
        string Number UK
        string Name
        string Address
    }
    ServiceConcern {
        uuid Id PK
        string Reference UK
        uuid SubmissionKey UK
        uuid CustomerAccountId FK
        uuid RecordedById FK
        string IntakeChannel
        string LegacyIntakeChannel
        int Category
        int State
        string Subject
        string Description
        string Location
        string Contact
        timestamptz SubmittedAt
        timestamptz FirstHumanResponseAt
        uuid Version
    }
    RepairTicket {
        uuid Id PK
        string Reference UK
        uuid ServiceConcernId FK,UK
        uuid PlumberResourceId FK
        int State
        timestamptz CreatedAt
        timestamptz FirstAssignedAt
        timestamptz ResolvedAt
        timestamptz ClosedAt
        string CompletionSummary
        string SignedJobOrder
        uuid Version
    }
    ConcernEvent {
        uuid Id PK
        uuid ServiceConcernId FK
        uuid ActorId FK
        timestamptz At
        string Kind
        int PreviousState
        int NewState
        int PreviousCategory
        int NewCategory
        string Text
        bool Internal
    }
    TicketEvent {
        uuid Id PK
        uuid RepairTicketId FK
        uuid ActorId FK
        uuid PlumberResourceId FK
        timestamptz At
        string Action
        int From
        int To
        string Text
        bool Internal
    }
    AuditRecord {
        uuid Id PK
        uuid ActorId FK
        uuid RecordId
        timestamptz At
        string Operation
    }
```

AuditRecord.RecordId is an intentional polymorphic reference (concern or ticket), not an unconstrained account owner. The required actor is a foreign key; domain event tables provide the strict per-record foreign keys. Search and queue indexes cover category/state, account/time, reference uniqueness, and event record/time. See the migration for exact column types, limits, requiredness, and constraints.

Phase 2 categories and intake channels are domain enums constrained on the concern table, rather than editable lookup tables. Human responses are append-only ConcernEvent rows (Kind = Human response); a separate ConcernResponse table is unnecessary. State/category before/after values are nullable for pre-migration history; legacy evidence is preserved without inventing past state changes. Internal visibility is stored per event. The first response timestamp is nullable; Version is an EF concurrency token. Reference values default from concern_reference_seq; gaps on rollback are expected. SubmissionKey uniquely identifies a retriable form submission. Repair tables/relationships are retained for Phase 3; Phase 2 cannot create or update repair tickets.
