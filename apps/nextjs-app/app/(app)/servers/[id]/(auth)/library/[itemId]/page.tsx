import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { getServer } from "@/lib/db/server";
import { getItemDetails } from "@/lib/db/items";
import { getItemHistory } from "@/lib/db/history";
import { showAdminStatistics } from "@/utils/adminTools";
import { redirect } from "next/navigation";
import { ItemHeader } from "./ItemHeader";
import { ItemMetadata } from "./ItemMetadata";
import { ItemSessions } from "./ItemSessions";
import { getMe } from "@/lib/db/users";

export default async function ItemDetailsPage({
  params,
}: {
  params: Promise<{ id: string; itemId: string }>;
}) {
  const { id, itemId } = await params;
  const server = await getServer({ serverId: id });

  if (!server) {
    redirect("/not-found");
  }

  const me = await getMe();
  const showAdmin = await showAdminStatistics();

  const itemDetails = await getItemDetails({
    itemId,
    userId: showAdmin ? undefined : me?.id,
  });

  if (!itemDetails) {
    redirect("/not-found");
  }

  // Get initial session data for the item
  const initialSessionData = await getItemHistory(parseInt(id), itemId, 1, 20);

  return (
    <Container className="flex flex-col w-screen md:w-[calc(100vw-256px)]">
      <PageTitle
        title={itemDetails.item.name}
        subtitle={`${itemDetails.item.type} Details`}
      />

      <div className="space-y-6">
        <ItemHeader
          item={itemDetails.item}
          server={server}
          statistics={itemDetails}
        />
        <ItemMetadata item={itemDetails.item} statistics={itemDetails} />
        <ItemSessions 
          itemId={itemId}
          serverId={parseInt(id)}
          server={server}
          initialData={initialSessionData}
        />
      </div>
    </Container>
  );
}
