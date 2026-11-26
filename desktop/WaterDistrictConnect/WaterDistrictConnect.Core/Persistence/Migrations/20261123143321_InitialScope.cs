using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace WaterDistrictConnect.Core.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class InitialScope : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Accounts",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Number = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Address = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Accounts", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Plumbers",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Available = table.Column<bool>(type: "boolean", nullable: false),
                    AvailabilityNote = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Plumbers", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Roles",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Roles", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Users",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Username = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    PasswordHash = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    DisplayName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Users", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "RolePermission",
                columns: table => new
                {
                    RoleId = table.Column<int>(type: "integer", nullable: false),
                    Permission = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RolePermission", x => new { x.RoleId, x.Permission });
                    table.ForeignKey(
                        name: "FK_RolePermission_Roles_RoleId",
                        column: x => x.RoleId,
                        principalTable: "Roles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "Audits",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ActorId = table.Column<Guid>(type: "uuid", nullable: false),
                    At = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    Operation = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    RecordId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Audits", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Audits_Users_ActorId",
                        column: x => x.ActorId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "Concerns",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Reference = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    CustomerAccountId = table.Column<Guid>(type: "uuid", nullable: false),
                    RecordedById = table.Column<Guid>(type: "uuid", nullable: false),
                    IntakeChannel = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Category = table.Column<int>(type: "integer", nullable: false),
                    State = table.Column<int>(type: "integer", nullable: false),
                    Subject = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    Description = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: false),
                    Location = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    Contact = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    SubmittedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    FirstHumanResponseAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Version = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Concerns", x => x.Id);
                    table.CheckConstraint("CK_Concern_Category", "\"Category\" BETWEEN 0 AND 2");
                    table.CheckConstraint("CK_Concern_Content", "length(trim(\"Subject\")) > 0 AND length(trim(\"Description\")) > 0 AND length(trim(\"Location\")) > 0");
                    table.CheckConstraint("CK_Concern_State", "\"State\" BETWEEN 0 AND 3");
                    table.ForeignKey(
                        name: "FK_Concerns_Accounts_CustomerAccountId",
                        column: x => x.CustomerAccountId,
                        principalTable: "Accounts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_Concerns_Users_RecordedById",
                        column: x => x.RecordedById,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "Ownerships",
                columns: table => new
                {
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CustomerAccountId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Ownerships", x => new { x.UserId, x.CustomerAccountId });
                    table.ForeignKey(
                        name: "FK_Ownerships_Accounts_CustomerAccountId",
                        column: x => x.CustomerAccountId,
                        principalTable: "Accounts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_Ownerships_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "UserRole",
                columns: table => new
                {
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    RoleId = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UserRole", x => new { x.UserId, x.RoleId });
                    table.ForeignKey(
                        name: "FK_UserRole_Roles_RoleId",
                        column: x => x.RoleId,
                        principalTable: "Roles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_UserRole_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "ConcernEvents",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ServiceConcernId = table.Column<Guid>(type: "uuid", nullable: false),
                    ActorId = table.Column<Guid>(type: "uuid", nullable: false),
                    At = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    Kind = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Text = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: false),
                    Internal = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ConcernEvents", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ConcernEvents_Concerns_ServiceConcernId",
                        column: x => x.ServiceConcernId,
                        principalTable: "Concerns",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_ConcernEvents_Users_ActorId",
                        column: x => x.ActorId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "Tickets",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Reference = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    ServiceConcernId = table.Column<Guid>(type: "uuid", nullable: false),
                    PlumberResourceId = table.Column<Guid>(type: "uuid", nullable: true),
                    State = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    FirstAssignedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ResolvedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ClosedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CompletionSummary = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: false),
                    SignedJobOrder = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    Version = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Tickets", x => x.Id);
                    table.CheckConstraint("CK_Ticket_Assignment", "\"State\" NOT IN (1,2,3,4) OR \"PlumberResourceId\" IS NOT NULL");
                    table.CheckConstraint("CK_Ticket_Closure", "\"State\" <> 4 OR (length(trim(\"SignedJobOrder\")) > 0 AND \"ClosedAt\" IS NOT NULL)");
                    table.CheckConstraint("CK_Ticket_Completion", "\"State\" NOT IN (3,4) OR (length(trim(\"CompletionSummary\")) > 0 AND \"ResolvedAt\" IS NOT NULL)");
                    table.CheckConstraint("CK_Ticket_State", "\"State\" BETWEEN 0 AND 4");
                    table.ForeignKey(
                        name: "FK_Tickets_Concerns_ServiceConcernId",
                        column: x => x.ServiceConcernId,
                        principalTable: "Concerns",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_Tickets_Plumbers_PlumberResourceId",
                        column: x => x.PlumberResourceId,
                        principalTable: "Plumbers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "TicketEvents",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    RepairTicketId = table.Column<Guid>(type: "uuid", nullable: false),
                    ActorId = table.Column<Guid>(type: "uuid", nullable: false),
                    At = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    Action = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    From = table.Column<int>(type: "integer", nullable: false),
                    To = table.Column<int>(type: "integer", nullable: false),
                    Text = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: false),
                    Internal = table.Column<bool>(type: "boolean", nullable: false),
                    PlumberResourceId = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TicketEvents", x => x.Id);
                    table.ForeignKey(
                        name: "FK_TicketEvents_Plumbers_PlumberResourceId",
                        column: x => x.PlumberResourceId,
                        principalTable: "Plumbers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_TicketEvents_Tickets_RepairTicketId",
                        column: x => x.RepairTicketId,
                        principalTable: "Tickets",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_TicketEvents_Users_ActorId",
                        column: x => x.ActorId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Accounts_Number",
                table: "Accounts",
                column: "Number",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Audits_ActorId",
                table: "Audits",
                column: "ActorId");

            migrationBuilder.CreateIndex(
                name: "IX_ConcernEvents_ActorId",
                table: "ConcernEvents",
                column: "ActorId");

            migrationBuilder.CreateIndex(
                name: "IX_ConcernEvents_ServiceConcernId_At",
                table: "ConcernEvents",
                columns: new[] { "ServiceConcernId", "At" });

            migrationBuilder.CreateIndex(
                name: "IX_Concerns_CustomerAccountId_SubmittedAt",
                table: "Concerns",
                columns: new[] { "CustomerAccountId", "SubmittedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_Concerns_RecordedById",
                table: "Concerns",
                column: "RecordedById");

            migrationBuilder.CreateIndex(
                name: "IX_Concerns_Reference",
                table: "Concerns",
                column: "Reference",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Concerns_State_Category",
                table: "Concerns",
                columns: new[] { "State", "Category" });

            migrationBuilder.CreateIndex(
                name: "IX_Ownerships_CustomerAccountId",
                table: "Ownerships",
                column: "CustomerAccountId");

            migrationBuilder.CreateIndex(
                name: "IX_Ownerships_UserId",
                table: "Ownerships",
                column: "UserId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Plumbers_Name",
                table: "Plumbers",
                column: "Name",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Roles_Name",
                table: "Roles",
                column: "Name",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_TicketEvents_ActorId",
                table: "TicketEvents",
                column: "ActorId");

            migrationBuilder.CreateIndex(
                name: "IX_TicketEvents_PlumberResourceId",
                table: "TicketEvents",
                column: "PlumberResourceId");

            migrationBuilder.CreateIndex(
                name: "IX_TicketEvents_RepairTicketId_At",
                table: "TicketEvents",
                columns: new[] { "RepairTicketId", "At" });

            migrationBuilder.CreateIndex(
                name: "IX_Tickets_PlumberResourceId",
                table: "Tickets",
                column: "PlumberResourceId");

            migrationBuilder.CreateIndex(
                name: "IX_Tickets_Reference",
                table: "Tickets",
                column: "Reference",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Tickets_ServiceConcernId",
                table: "Tickets",
                column: "ServiceConcernId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_UserRole_RoleId",
                table: "UserRole",
                column: "RoleId");

            migrationBuilder.CreateIndex(
                name: "IX_Users_Username",
                table: "Users",
                column: "Username",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Audits");

            migrationBuilder.DropTable(
                name: "ConcernEvents");

            migrationBuilder.DropTable(
                name: "Ownerships");

            migrationBuilder.DropTable(
                name: "RolePermission");

            migrationBuilder.DropTable(
                name: "TicketEvents");

            migrationBuilder.DropTable(
                name: "UserRole");

            migrationBuilder.DropTable(
                name: "Tickets");

            migrationBuilder.DropTable(
                name: "Roles");

            migrationBuilder.DropTable(
                name: "Concerns");

            migrationBuilder.DropTable(
                name: "Plumbers");

            migrationBuilder.DropTable(
                name: "Accounts");

            migrationBuilder.DropTable(
                name: "Users");
        }
    }
}
