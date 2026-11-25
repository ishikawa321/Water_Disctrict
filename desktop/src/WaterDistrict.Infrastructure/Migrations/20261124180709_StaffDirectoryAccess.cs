using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace WaterDistrict.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class StaffDirectoryAccess : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(EmbeddedSql.Read("staff-access.sql"));
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            throw new NotSupportedException("Staff roles must be reviewed before removing Staff access.");
        }
    }
}
