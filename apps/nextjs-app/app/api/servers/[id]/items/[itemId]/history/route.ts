import { NextRequest, NextResponse } from "next/server";
import { getItemHistory } from "@/lib/db/history";
import { getServer } from "@/lib/db/server";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; itemId: string }> }
) {
  try {
    const { id, itemId } = await params;
    const { searchParams } = new URL(request.url);
    
    const page = parseInt(searchParams.get("page") || "1");
    const perPage = parseInt(searchParams.get("perPage") || "20");

    // Verify server exists
    const server = await getServer({ serverId: id });
    if (!server) {
      return NextResponse.json(
        { error: "Server not found" },
        { status: 404 }
      );
    }

    // Get item history
    const historyData = await getItemHistory(
      parseInt(id),
      itemId,
      page,
      perPage
    );

    return NextResponse.json(historyData);
  } catch (error) {
    console.error("Error fetching item history:", error);
    return NextResponse.json(
      { error: "Failed to fetch item history" },
      { status: 500 }
    );
  }
}
