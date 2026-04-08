"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { HistoryTable } from "../../history/HistoryTable";
import type { Server } from "@/lib/types";
import type { HistoryResponse } from "@/lib/db/history";
import { useState } from "react";
import { ChevronDown, Loader2 } from "lucide-react";

interface ItemSessionsProps {
  itemId: string;
  serverId: number;
  server: Server;
  initialData: HistoryResponse;
}

export function ItemSessions({ itemId, serverId, server, initialData }: ItemSessionsProps) {
  const [historyData, setHistoryData] = useState(initialData);
  const [isLoading, setIsLoading] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);

  const hasMorePages = currentPage < historyData.totalPages;

  const loadMoreSessions = async () => {
    if (isLoading || !hasMorePages) return;

    setIsLoading(true);
    try {
      const response = await fetch(
        `/api/servers/${serverId}/items/${itemId}/history?page=${currentPage + 1}&perPage=20`
      );
      
      if (!response.ok) {
        throw new Error('Failed to load more sessions');
      }

      const newData: HistoryResponse = await response.json();
      
      // Append new data to existing data
      setHistoryData(prev => ({
        ...newData,
        data: [...prev.data, ...newData.data]
      }));
      
      setCurrentPage(prev => prev + 1);
    } catch (error) {
      console.error('Error loading more sessions:', error);
    } finally {
      setIsLoading(false);
    }
  };

  if (!historyData.data || historyData.data.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Playback Sessions</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-muted-foreground">No playback sessions found for this item.</p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>
          Playback Sessions ({historyData.totalCount})
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <HistoryTable 
          data={historyData} 
          server={server}
          hideUserColumn={false}
        />
        
        {hasMorePages && (
          <div className="flex justify-center">
            <Button
              variant="outline"
              onClick={loadMoreSessions}
              disabled={isLoading}
              className="w-full max-w-xs"
            >
              {isLoading ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Loading...
                </>
              ) : (
                <>
                  <ChevronDown className="mr-2 h-4 w-4" />
                  Show More Sessions
                </>
              )}
            </Button>
          </div>
        )}
        
        {historyData.data.length > 0 && historyData.data.length < historyData.totalCount && (
          <p className="text-center text-sm text-muted-foreground">
            Showing {historyData.data.length} of {historyData.totalCount} sessions
          </p>
        )}
      </CardContent>
    </Card>
  );
}
