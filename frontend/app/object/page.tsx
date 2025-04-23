"use client";

import Image from "next/image";
import { useState, useEffect } from "react";
import {
  addressEllipsis,
  ConnectButton,
  ErrorCode,
  formatSUI,
  SuiChainId,
  useAccountBalance,
  useChain,
  useSuiClient,
  useWallet,
} from "@suiet/wallet-kit";

export default function ObjectPage() {
  const wallet = useWallet();
  const suiClient = useSuiClient();
  const { balance } = useAccountBalance();
  const chain = useChain();
  
  // 对象列表状态
  const [objects, setObjects] = useState<any[]>([]);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string>("");
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState<boolean>(false);
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [objectType, setObjectType] = useState<string>("");
  const [filterType, setFilterType] = useState<string>("");

  // 当钱包连接状态改变时，自动获取对象
  useEffect(() => {
    if (wallet.connected && wallet.account) {
      fetchObjects();
    } else {
      setObjects([]);
      setNextCursor(null);
      setHasMore(false);
      setCurrentPage(1);
    }
  }, [wallet.connected, wallet.account]);

  // 获取账户的所有对象
  const fetchObjects = async (cursor: string | null = null, reset: boolean = true) => {
    if (!wallet.account?.address) return;
    
    setLoading(true);
    setError("");
    
    try {
      console.log("开始获取账户对象，地址:", wallet.account.address);
      
      const queryOptions: any = {
        owner: wallet.account.address,
        options: {
          showContent: true,
          showType: true,
          showOwner: true,
          showDisplay: true,
        },
        cursor: cursor,
        limit: 20
      };
      
      // 如果设置了过滤类型，添加过滤条件
      if (filterType) {
        queryOptions.filter = {
          StructType: filterType
        };
      }
      
      // 获取钱包拥有的所有对象
      const response = await suiClient.getOwnedObjects(queryOptions);
      
      console.log("获取到对象响应:", response);
      
      // 处理分页信息
      setHasMore(response.hasNextPage);
      setNextCursor(response.nextCursor || null);
      
      const newObjects = response.data.map(item => ({
        id: item.data?.objectId || 'unknown',
        type: item.data?.type || 'unknown',
        content: item.data?.content || {},
        display: item.data?.display?.data || {}
      }));
      
      if (reset) {
        setObjects(newObjects);
        setCurrentPage(1);
      } else {
        setObjects(prev => [...prev, ...newObjects]);
        setCurrentPage(prev => prev + 1);
      }
      
      console.log(`获取到 ${newObjects.length} 个对象`);
      
    } catch (e) {
      console.error("获取对象失败", e);
      setError("获取对象失败，请刷新页面重试");
    } finally {
      setLoading(false);
    }
  };

  // 加载更多对象
  const loadMore = () => {
    if (hasMore && nextCursor) {
      fetchObjects(nextCursor, false);
    }
  };

  // 应用过滤器
  const applyFilter = () => {
    setFilterType(objectType);
    fetchObjects(null, true);
  };

  // 清除过滤器
  const clearFilter = () => {
    setObjectType("");
    setFilterType("");
    fetchObjects(null, true);
  };

  // 网络名称格式化
  const chainName = (chainId: string | undefined) => {
    switch (chainId) {
      case SuiChainId.MAIN_NET:
        return "主网";
      case SuiChainId.TEST_NET:
        return "测试网";
      case SuiChainId.DEV_NET:
        return "开发网";
      default:
        return "未知网络";
    }
  };

  // 格式化对象类型显示
  const formatType = (type: string) => {
    // 提取类型的最后部分（如果有::分隔）
    const parts = type.split('::');
    if (parts.length > 1) {
      return `${parts[parts.length - 2]}::${parts[parts.length - 1]}`;
    }
    return type;
  };

  return (
    <main className="flex min-h-screen flex-col items-center justify-between p-24">
      <div className="z-10 w-full max-w-5xl items-center justify-between font-mono text-sm lg:flex">
        <p className="fixed left-0 top-0 flex w-full justify-center border-b border-gray-300 bg-gradient-to-b from-zinc-200 pb-6 pt-8 backdrop-blur-2xl dark:border-neutral-800 dark:bg-zinc-800/30 dark:from-inherit lg:static lg:w-auto lg:rounded-xl lg:border lg:bg-gray-200 lg:p-4 lg:dark:bg-zinc-800/30">
          Nawhal.fi 对象浏览器
        </p>
        <div className="fixed bottom-0 left-0 flex h-48 w-full items-end justify-center bg-gradient-to-t from-white via-white dark:from-black dark:via-black lg:static lg:h-auto lg:w-auto lg:bg-none">
          <a
            className="pointer-events-none flex place-items-center gap-2 p-8 lg:pointer-events-auto lg:p-0"
            href="/"
            rel="noopener noreferrer"
          >
            返回首页
          </a>
        </div>
      </div>

      <div className="relative flex flex-col place-items-center before:absolute before:h-[300px] before:w-[480px] before:-translate-x-1/2 before:rounded-full before:bg-gradient-radial before:from-white before:to-transparent before:blur-2xl before:content-[''] after:absolute after:-z-20 after:h-[180px] after:w-[240px] after:translate-x-1/3 after:bg-gradient-conic after:from-sky-200 after:via-blue-200 after:blur-2xl after:content-[''] before:dark:bg-gradient-to-br before:dark:from-transparent before:dark:to-blue-700 before:dark:opacity-10 after:dark:from-sky-900 after:dark:via-[#0141ff] after:dark:opacity-40 before:lg:h-[360px]">
        <h1 className="text-4xl font-bold mb-8">账户对象浏览器</h1>

        <ConnectButton
          onConnectError={(error) => {
            if (error.code === ErrorCode.WALLET__CONNECT_ERROR__USER_REJECTED) {
              console.warn(
                "用户拒绝连接钱包: " + error.details?.wallet
              );
            } else {
              console.warn("连接错误: ", error);
            }
          }}
        />

        {!wallet.connected ? (
          <p className={"my-8"}>请连接钱包以查看您的对象</p>
        ) : (
          <div className={"my-8 w-full max-w-5xl"}>
            <div className="mb-8 p-4 bg-gray-100 dark:bg-gray-800 rounded-lg">
              <p>当前钱包: {wallet.adapter?.name}</p>
              <p>
                钱包状态:{" "}
                {wallet.connecting
                  ? "连接中"
                  : wallet.connected
                  ? "已连接"
                  : "未连接"}
              </p>
              <p>
                钱包地址: {addressEllipsis(wallet.account?.address ?? "")}
              </p>
              <p>
                当前网络: {chainName(wallet.chain?.id)}
              </p>
              <p>
                钱包余额:{" "}
                {formatSUI(balance ?? 0, {
                  withAbbr: false,
                })}{" "}
                SUI
              </p>
            </div>
            
            {error && (
              <div className="w-full mb-4 p-3 bg-red-100 text-red-700 rounded-lg">
                {error}
              </div>
            )}
            
            <div className="w-full mb-6">
              <div className="flex items-center gap-2 mb-4">
                <input
                  type="text"
                  placeholder="输入对象类型进行过滤，例如 0x2::coin::Coin"
                  value={objectType}
                  onChange={(e) => setObjectType(e.target.value)}
                  className="flex-1 bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg p-2.5"
                />
                <button 
                  onClick={applyFilter}
                  className="bg-blue-600 hover:bg-blue-700 text-white py-2 px-4 rounded"
                  disabled={loading}
                >
                  应用过滤
                </button>
                <button 
                  onClick={clearFilter}
                  className="bg-gray-500 hover:bg-gray-600 text-white py-2 px-4 rounded"
                  disabled={loading || !filterType}
                >
                  清除过滤
                </button>
              </div>
              
              <div className="bg-white dark:bg-gray-900 rounded-lg shadow overflow-hidden">
                <div className="px-4 py-3 border-b border-gray-200 dark:border-gray-700 flex justify-between items-center">
                  <h3 className="text-lg font-medium">
                    账户对象 ({objects.length}个)
                    {filterType && <span className="ml-2 text-sm text-gray-500">- 类型: {filterType}</span>}
                  </h3>
                  <button 
                    onClick={() => fetchObjects()}
                    className="text-blue-600 hover:text-blue-800 text-sm"
                    disabled={loading}
                  >
                    {loading ? '加载中...' : '刷新'}
                  </button>
                </div>
                
                {loading && objects.length === 0 ? (
                  <div className="p-6 text-center">加载中...</div>
                ) : objects.length === 0 ? (
                  <div className="p-6 text-center">未找到对象{filterType ? '（尝试清除过滤器）' : ''}</div>
                ) : (
                  <div className="divide-y divide-gray-200 dark:divide-gray-700">
                    {objects.map((object, index) => (
                      <div 
                        key={object.id + index} 
                        className="p-4 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
                      >
                        <div className="mb-2 flex justify-between">
                          <span className="font-medium">ID: </span>
                          <span className="break-all">{object.id}</span>
                        </div>
                        <div className="mb-2 flex justify-between">
                          <span className="font-medium">类型: </span>
                          <span className="break-all text-blue-600">{formatType(object.type)}</span>
                        </div>
                        {object.display.name && (
                          <div className="mb-2 flex justify-between">
                            <span className="font-medium">名称: </span>
                            <span>{object.display.name}</span>
                          </div>
                        )}
                        {object.display.description && (
                          <div className="mb-2 flex justify-between">
                            <span className="font-medium">描述: </span>
                            <span>{object.display.description}</span>
                          </div>
                        )}
                        <div className="mt-3">
                          <details className="cursor-pointer">
                            <summary className="text-sm text-gray-500">查看详细内容</summary>
                            <pre className="mt-2 p-3 bg-gray-100 dark:bg-gray-800 rounded text-xs overflow-auto max-h-60">
                              {JSON.stringify(object.content, null, 2)}
                            </pre>
                          </details>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
                
                {hasMore && (
                  <div className="p-4 text-center">
                    <button
                      onClick={loadMore}
                      disabled={loading}
                      className="bg-blue-600 hover:bg-blue-700 text-white py-2 px-4 rounded"
                    >
                      {loading ? '加载中...' : '加载更多'}
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        )}
      </div>

      <div className="mb-32 grid text-center lg:mb-0 lg:grid-cols-3 lg:text-left">
        <a
          href="/"
          className="group rounded-lg border border-transparent px-5 py-4 transition-colors hover:border-gray-300 hover:bg-gray-100 hover:dark:border-neutral-700 hover:dark:bg-neutral-800/30"
        >
          <h2 className={`mb-3 text-2xl font-semibold`}>
            主页{" "}
            <span className="inline-block transition-transform group-hover:translate-x-1 motion-reduce:transform-none">
              -&gt;
            </span>
          </h2>
          <p className={`m-0 max-w-[30ch] text-sm opacity-50`}>
            返回Nawhal.fi主页。
          </p>
        </a>

        <a
          href="/lending"
          className="group rounded-lg border border-transparent px-5 py-4 transition-colors hover:border-gray-300 hover:bg-gray-100 hover:dark:border-neutral-700 hover:dark:bg-neutral-800/30"
        >
          <h2 className={`mb-3 text-2xl font-semibold`}>
            借贷协议{" "}
            <span className="inline-block transition-transform group-hover:translate-x-1 motion-reduce:transform-none">
              -&gt;
            </span>
          </h2>
          <p className={`m-0 max-w-[30ch] text-sm opacity-50`}>
            尝试Nawhal.fi的借贷功能。
          </p>
        </a>

        <a
          href="https://docs.sui.io/"
          target="_blank"
          rel="noopener noreferrer"
          className="group rounded-lg border border-transparent px-5 py-4 transition-colors hover:border-gray-300 hover:bg-gray-100 hover:dark:border-neutral-700 hover:dark:bg-neutral-800/30"
        >
          <h2 className={`mb-3 text-2xl font-semibold`}>
            Sui 文档{" "}
            <span className="inline-block transition-transform group-hover:translate-x-1 motion-reduce:transform-none">
              -&gt;
            </span>
          </h2>
          <p className={`m-0 max-w-[30ch] text-sm opacity-50`}>
            了解更多关于Sui区块链的信息。
          </p>
        </a>
      </div>
    </main>
  );
} 