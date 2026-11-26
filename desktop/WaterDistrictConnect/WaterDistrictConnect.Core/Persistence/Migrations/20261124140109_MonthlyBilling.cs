using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace WaterDistrictConnect.Core.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class MonthlyBilling : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Bills",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CustomerAccountId = table.Column<Guid>(type: "uuid", nullable: false),
                    Month = table.Column<DateOnly>(type: "date", nullable: false),
                    DueDate = table.Column<DateOnly>(type: "date", nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(11,2)", precision: 11, scale: 2, nullable: false),
                    PaidAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    Version = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Bills", x => x.Id);
                    table.CheckConstraint("CK_Bill_Amount", "\"Amount\" > 0");
                    table.CheckConstraint("CK_Bill_Dates", "EXTRACT(DAY FROM \"Month\") = 1 AND \"DueDate\" >= \"Month\"");
                    table.ForeignKey(
                        name: "FK_Bills_Accounts_CustomerAccountId",
                        column: x => x.CustomerAccountId,
                        principalTable: "Accounts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Bills_CustomerAccountId_Month",
                table: "Bills",
                columns: new[] { "CustomerAccountId", "Month" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Bills");
        }
    }
}
