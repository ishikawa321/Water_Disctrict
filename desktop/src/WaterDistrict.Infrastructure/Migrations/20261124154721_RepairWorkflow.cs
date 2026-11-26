using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace WaterDistrict.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class RepairWorkflow : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "public");

            migrationBuilder.Sql(EmbeddedSql.Read("upgrade-preflight.sql"));
            migrationBuilder.CreateTable(
                name: "ticket_status_history",
                schema: "public",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    ticket_id = table.Column<Guid>(type: "uuid", nullable: false),
                    changed_by = table.Column<Guid>(type: "uuid", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    note = table.Column<string>(type: "text", nullable: false),
                    assigned_to_user_id = table.Column<Guid>(type: "uuid", nullable: true),
                    assigned_to = table.Column<string>(type: "text", nullable: true),
                    changed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ticket_status_history", x => x.id);
                    table.ForeignKey(
                        name: "FK_ticket_status_history_profiles_changed_by",
                        column: x => x.changed_by,
                        principalSchema: "public",
                        principalTable: "profiles",
                        principalColumn: "user_id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_ticket_status_history_repair_tickets_ticket_id",
                        column: x => x.ticket_id,
                        principalSchema: "public",
                        principalTable: "repair_tickets",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ticket_status_history_changed_by",
                schema: "public",
                table: "ticket_status_history",
                column: "changed_by");

            migrationBuilder.CreateIndex(
                name: "IX_ticket_status_history_ticket_id_id",
                schema: "public",
                table: "ticket_status_history",
                columns: new[] { "ticket_id", "id" });
            migrationBuilder.Sql(EmbeddedSql.Read("workflow-triggers.sql"));
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            throw new NotSupportedException("Restore a reviewed backup instead of dropping operational ticket history.");
        }
    }
}
