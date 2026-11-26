using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace WaterDistrictConnect.Core.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Phase2Concerns : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "CK_Concern_Category",
                table: "Concerns");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Concern_State",
                table: "Concerns");

            migrationBuilder.CreateSequence(
                name: "concern_reference_seq",
                startValue: 100001L);

            migrationBuilder.AlterColumn<string>(
                name: "Reference",
                table: "Concerns",
                type: "character varying(200)",
                maxLength: 200,
                nullable: false,
                defaultValueSql: "'MWD-' || nextval('concern_reference_seq')::text",
                oldClrType: typeof(string),
                oldType: "character varying(200)",
                oldMaxLength: 200);

            migrationBuilder.AddColumn<string>(
                name: "LegacyIntakeChannel",
                table: "Concerns",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);

            // Preserve original intake text before normalizing to the four supported channel values.
            migrationBuilder.Sql("""
                UPDATE "Concerns" SET "LegacyIntakeChannel" = "IntakeChannel",
                "IntakeChannel" = CASE lower("IntakeChannel")
                  WHEN 'desktop client' THEN 'DesktopClient' WHEN 'desktopclient' THEN 'DesktopClient'
                  WHEN 'telephone' THEN 'Telephone' WHEN 'office visit' THEN 'WalkIn'
                  WHEN 'walk-in' THEN 'WalkIn' WHEN 'walkin' THEN 'WalkIn' ELSE 'Other' END;
                """);
            migrationBuilder.AlterColumn<string>(
                name: "IntakeChannel",
                table: "Concerns",
                type: "character varying(40)",
                maxLength: 40,
                nullable: false,
                oldClrType: typeof(string),
                oldType: "character varying(200)",
                oldMaxLength: 200);

            migrationBuilder.AddColumn<Guid>(
                name: "SubmissionKey",
                table: "Concerns",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"));

            migrationBuilder.AddColumn<int>(
                name: "NewCategory",
                table: "ConcernEvents",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "NewState",
                table: "ConcernEvents",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "PreviousCategory",
                table: "ConcernEvents",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "PreviousState",
                table: "ConcernEvents",
                type: "integer",
                nullable: true);

            migrationBuilder.Sql("""
                UPDATE "Concerns" SET "SubmissionKey" = gen_random_uuid();
                SELECT setval('concern_reference_seq', GREATEST(100000,
                  COALESCE((SELECT max(substring("Reference" from 5)::bigint) FROM "Concerns" WHERE "Reference" ~ '^MWD-[0-9]{1,15}$'), 0)), true);
                """);

            migrationBuilder.CreateIndex(
                name: "IX_Concerns_SubmissionKey",
                table: "Concerns",
                column: "SubmissionKey",
                unique: true);

            migrationBuilder.AddCheckConstraint(
                name: "CK_Concern_Category",
                table: "Concerns",
                sql: "\"Category\" BETWEEN 0 AND 4");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Concern_Channel",
                table: "Concerns",
                sql: "\"IntakeChannel\" IN ('DesktopClient','Telephone','WalkIn','Other')");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Concern_State",
                table: "Concerns",
                sql: "\"State\" BETWEEN 0 AND 4");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            throw new NotSupportedException("Phase 2 preserves expanded categories and history. Use a reviewed forward migration rather than discarding recorded data.");
        }
    }
}
