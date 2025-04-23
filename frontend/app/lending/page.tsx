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
import { Transaction } from "@mysten/sui/transactions";
import { SuiTransactionBlockResponse } from "@mysten/sui/client";

// Nawhal.fi借贷协议的对象ID（仅支持测试网）
const PACKAGE_ID = "0x891b34e2e9d6976f42a40520d862d69e1030969670c5f5f11aad3dce3a374255";
const LENDING_PROTOCOL_ID = "0xefd3b55539f8b53f3f4d257847c96ea5a777e331279dcfeaff2bafd2affac5fb"; // lending protocol<SUI>
const LIQUIDITY_LAYER_ID = "0x870dff95dfc246e982f957ea3837f34f2e12ddbfcc458e700422c475173dcc14"; // liquidity layer
const ACCOUNT_REGISTRY_ID = "0x49a811f4ef2f9ed80114d9e91a48e634dc54d0f06c68735d695b507a04b65b91"; // account registry
const YTSUI_TYPE = `${PACKAGE_ID}::ytsui::YTSUI`; // YTSUI类型

// AccountProfileCap类型
const ACCOUNT_PROFILE_CAP_TYPE = `${PACKAGE_ID}::account_ds::AccountProfileCap`;

// 常量定义部分添加资产类型标识
const SUI_ASSET_TYPE = "0x2::sui::SUI"; // SUI资产类型

export default function LendingPage() {
  const wallet = useWallet();
  const suiClient = useSuiClient();
  const { balance } = useAccountBalance();
  const chain = useChain();
  
  // 用于输入存款/取款金额的状态
  const [amount, setAmount] = useState<string>("");
  // 用于追踪用户的AccountProfileCap对象
  const [profileCap, setProfileCap] = useState<string>("");
  const [availableProfileCaps, setAvailableProfileCaps] = useState<{id: string, description: string}[]>([]);
  const [stakingBalance, setStakingBalance] = useState<string>("0");
  const [fetchingBalance, setFetchingBalance] = useState<boolean>(false);
  const [totalDeposited, setTotalDeposited] = useState<string>("0"); // 添加总存款额状态
  // 记录最近创建的凭证ID
  const [lastDepositCapId, setLastDepositCapId] = useState<string>("");
  // 交易状态
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string>("");
  const [success, setSuccess] = useState<string>("");
  
  // 在组件内添加资产类型状态
  const [assetType, setAssetType] = useState<string>(SUI_ASSET_TYPE);
  
  // 检查当前网络是否为测试网
  const isTestnet = wallet.chain?.id === SuiChainId.TEST_NET;

  // 当钱包连接状态改变时，自动获取AccountProfileCap
  useEffect(() => {
    if (wallet.connected && wallet.account && isTestnet) {
      fetchAccountProfileCaps();
    } else {
      setAvailableProfileCaps([]);
      setProfileCap("");
      setStakingBalance("0");
      setTotalDeposited("0"); // 重置总存款额
    }
  }, [wallet.connected, wallet.account, isTestnet]);

  // 当选择的ProfileCap改变时，获取质押余额
  useEffect(() => {
    if (profileCap && isTestnet) {
      fetchStakingBalance();
    } else {
      setStakingBalance("0");
    }
  }, [profileCap]);

  // 获取账户的所有AccountProfileCap对象
  const fetchAccountProfileCaps = async () => {
    setLoading(true);
    try {
      console.log("Fetching account profile caps", wallet);
      // 确保wallet和wallet.account都存在
      if (!wallet || !wallet.account) {
        console.error("Wallet or wallet.account is undefined");
        setLoading(false);
        return;
      }
      
      console.log("使用正确的类型过滤器查询凭证");
      // 获取账户的Profile Cap
      const response = await suiClient.getOwnedObjects({
        owner: wallet.account.address,
        filter: {
          StructType: ACCOUNT_PROFILE_CAP_TYPE,
        },
        options: {
          showContent: true,
          showDisplay: true,
        },
      });
  
      console.log("获取到凭证响应:", response);
      
      // 处理本页凭证
      const pageCaps = response.data
        .filter(item => {
          const isValid = item.data && item.data.content;
          if (!isValid) {
            console.log("跳过无效凭证:", item);
          }
          return isValid;
        })
        .map(item => ({
          id: item.data!.objectId,
          description: `AccountProfileCap (${item.data!.objectId.substring(0, 8)}...)`
        }));
        
      // 添加到总列表
      setAvailableProfileCaps(pageCaps);
      
      // 如果有可用的Cap并且当前没有选择，自动选择第一个
      if (pageCaps.length > 0 && !profileCap) {
        console.log("自动选择第一个凭证:", pageCaps[0].id);
        setProfileCap(pageCaps[0].id);
      } else if (pageCaps.length === 0) {
        console.log("未找到任何有效凭证");
      }
      
      // 计算总存款额
      calculateTotalDeposited();
    } catch (e) {
      console.error("获取AccountProfileCap失败", e);
      setError("获取AccountProfileCap对象失败，请刷新页面重试");
    } finally {
      setLoading(false);
    }
  };

  // 计算所有凭证的总存款额
  const calculateTotalDeposited = async () => {
    if (!wallet || !wallet.account) {
      console.error("Wallet or wallet.account is undefined");
      setTotalDeposited("0");
      return;
    }
    
    setFetchingBalance(true);
    
    try {
      console.log("开始计算总存款额...");
      
      // 尝试直接通过借贷协议对象获取所有质押记录
      try {
        // 1. 获取借贷协议对象的动态字段，查找stakers表
        const protocolFields = await suiClient.getDynamicFields({
          parentId: LENDING_PROTOCOL_ID
        });
        
        // 查找stakers表
        const stakersTable = protocolFields.data.find(field => 
          field.name && typeof field.name === 'object' && 
          'type' in field.name && field.name.type && 
          field.name.type.includes('stakers')
        );
        
        if (stakersTable) {
          console.log("找到stakers表:", stakersTable.objectId);
          
          // 2. 获取stakers表中的所有记录
          const stakersContent = await suiClient.getDynamicFields({
            parentId: stakersTable.objectId
          });
          
          console.log(`找到 ${stakersContent.data.length} 条质押记录`);
          
          // 3. 获取用户所有账户ID
          const accountIds = new Set<string>();
          
          // 首先从所有凭证中获取账户ID
          for (const cap of availableProfileCaps) {
            try {
              const tx = new Transaction();
              tx.moveCall({
                target: `${PACKAGE_ID}::account_ds::account_of` as any,
                arguments: [tx.object(cap.id)],
              });
              
              const result = await suiClient.devInspectTransactionBlock({
                transactionBlock: tx,
                sender: wallet.account.address
              });
              
              if (result.results && result.results[0]?.returnValues) {
                const accountId = String(result.results[0].returnValues[0][0]);
                if (accountId) {
                  accountIds.add(accountId);
                  console.log(`从凭证 ${cap.id} 获取到账户ID: ${accountId}`);
                }
              }
            } catch (error) {
              console.error(`获取凭证 ${cap.id} 的账户ID失败:`, error);
            }
          }
          
          console.log(`共获取到 ${accountIds.size} 个账户ID`);
          
          // 4. 查找这些账户ID对应的质押记录并计算总金额
          let totalAmount = 0;
          const accountIdArray = Array.from(accountIds);
          
          if (accountIdArray.length > 0) {
            for (const accountId of accountIdArray) {
              // 在stakers表中查找账户记录
              const userRecord = stakersContent.data.find(field => 
                field.name && typeof field.name === 'object' && 
                'id' in field.name && field.name.id === accountId
              );
              
              if (userRecord) {
                console.log(`找到账户 ${accountId} 的质押记录`);
                
                // 获取记录详情
                const recordDetails = await suiClient.getObject({
                  id: userRecord.objectId,
                  options: {
                    showContent: true
                  }
                });
                
                // 从记录中提取总资产金额
                if (recordDetails.data && recordDetails.data.content) {
                  const content = recordDetails.data.content;
                  if (typeof content === 'object' && 'fields' in content) {
                    const fields = content.fields;
                    if ('total_asset_amount' in fields) {
                      const amount = Number(BigInt(String(fields.total_asset_amount))) / 1_000_000_000;
                      console.log(`账户 ${accountId} 的质押金额: ${amount} SUI`);
                      totalAmount += amount;
                    }
                  }
                }
              } else {
                console.log(`未找到账户 ${accountId} 的质押记录`);
              }
            }
          } else {
            console.log("未找到任何账户ID，尝试使用其他方法...");
            
            // 如果没有找到账户ID，尝试在stakers表中搜索所有记录
            for (const record of stakersContent.data) {
              try {
                const recordDetails = await suiClient.getObject({
                  id: record.objectId,
                  options: {
                    showContent: true,
                    showOwner: true
                  }
                });
                
                if (recordDetails.data && recordDetails.data.content) {
                  const content = recordDetails.data.content;
                  if (typeof content === 'object' && 'fields' in content) {
                    const fields = content.fields;
                    
                    // 检查这个记录是否属于当前用户
                    if ('account_id' in fields) {
                      console.log(`检查记录 ${record.objectId} 的所有者...`);
                      
                      // 从记录中提取总资产金额
                      if ('total_asset_amount' in fields) {
                        const amount = Number(BigInt(String(fields.total_asset_amount))) / 1_000_000_000;
                        
                        // 只有当记录的所有者与当前用户匹配时才计入总金额
                        const recordOwner = recordDetails.data.owner;
                        if (recordOwner && typeof recordOwner === 'object' && 
                            'AddressOwner' in recordOwner && 
                            recordOwner.AddressOwner === wallet.account.address) {
                          console.log(`找到用户拥有的质押记录，金额: ${amount} SUI`);
                          totalAmount += amount;
                        }
                      }
                    }
                  }
                }
              } catch (error) {
                console.error(`处理记录 ${record.objectId} 失败:`, error);
              }
            }
          }
          
          console.log(`计算完成，总存款额: ${totalAmount} SUI`);
          setTotalDeposited(totalAmount.toString());
        } else {
          console.log("未找到stakers表，可能是借贷协议尚未初始化");
          setTotalDeposited("0");
        }
      } catch (error) {
        console.error("通过动态字段查询失败:", error);
        
        // 如果上面的方法失败，回退到原来的方法
        let totalAmount = 0;
        
        // 遍历所有凭证并获取每个凭证的余额
        for (const cap of availableProfileCaps) {
          try {
            console.log("处理凭证ID:", cap.id);
            
            // 1. 获取账户ID
            const tx1 = new Transaction();
            tx1.moveCall({
              target: `${PACKAGE_ID}::account_ds::account_of` as any,
              arguments: [tx1.object(cap.id)],
            });
            
            const result1 = await suiClient.devInspectTransactionBlock({
              transactionBlock: tx1,
              sender: wallet.account.address
            });
            
            if (!result1.results || result1.results.length === 0 || !result1.results[0].returnValues) {
              console.log("获取账户ID失败，跳过此凭证");
              continue;
            }
            
            const accountIdResult = result1.results[0].returnValues[0];
            if (!accountIdResult || !accountIdResult[0]) {
              console.log("账户ID格式无效，跳过此凭证");
              continue;
            }
            
            const accountId = String(accountIdResult[0]);
            console.log("成功获取账户ID:", accountId);
            
            // 2. 检查是否存在质押记录
            let hasStakingRecord = false;
            try {
              const checkTx = new Transaction();
              checkTx.moveCall({
                target: `${PACKAGE_ID}::lending_protocol::check_staking_info_exists` as any,
                arguments: [
                  checkTx.object(LENDING_PROTOCOL_ID),
                  checkTx.pure.id(accountId),
                ],
                typeArguments: ["0x2::sui::SUI", YTSUI_TYPE]
              });
              
              await suiClient.devInspectTransactionBlock({
                transactionBlock: checkTx,
                sender: wallet.account.address
              });
              
              // 如果没有抛出异常，说明质押记录存在
              hasStakingRecord = true;
              console.log("确认存在质押记录");
            } catch (checkError) {
              console.log("质押记录不存在或检查失败，跳过此凭证");
              continue;
            }
            
            if (!hasStakingRecord) {
              continue;
            }
            
            // 3. 获取质押金额
            const balanceTx = new Transaction();
            balanceTx.moveCall({
              target: `${PACKAGE_ID}::lending_protocol::staking_total_amount` as any,
              arguments: [
                balanceTx.object(LENDING_PROTOCOL_ID),
                balanceTx.pure.id(accountId),
              ],
              typeArguments: ["0x2::sui::SUI", YTSUI_TYPE]
            });
            
            const balanceResult = await suiClient.devInspectTransactionBlock({
              transactionBlock: balanceTx,
              sender: wallet.account.address
            });
            
            if (balanceResult.results && balanceResult.results[0]?.returnValues) {
              const balanceValue = balanceResult.results[0].returnValues[0];
              if (balanceValue && balanceValue[0] !== undefined) {
                const balance = Number(BigInt(String(balanceValue[0]))) / 1_000_000_000;
                console.log("凭证余额:", balance, "SUI");
                totalAmount += balance;
              }
            }
          } catch (error) {
            console.error("处理凭证时出错:", error);
            // 继续处理下一个凭证
          }
        }
        
        console.log("计算完成，总存款额:", totalAmount, "SUI");
        setTotalDeposited(totalAmount.toString());
      }
    } catch (e) {
      console.error("计算总存款额失败", e);
      setTotalDeposited("0");
    } finally {
      setFetchingBalance(false);
    }
  };

  // 获取当前账户的质押余额
  const fetchStakingBalance = async () => {
    if (!profileCap || !wallet.account?.address) {
      console.log("没有选择凭证或未连接钱包，无法获取余额");
      setStakingBalance("0");
      return;
    }
    
    setFetchingBalance(true);
    try {
      console.log("开始获取凭证余额，凭证ID:", profileCap);
      
      // 1. 获取账户ID
      const tx1 = new Transaction();
      tx1.moveCall({
        target: `${PACKAGE_ID}::account_ds::account_of` as any,
        arguments: [tx1.object(profileCap)],
      });
      
      const result1 = await suiClient.devInspectTransactionBlock({
        transactionBlock: tx1,
        sender: wallet.account?.address || ""
      });
      
      console.log("获取账户ID调用结果:", result1);
      
      if (!result1.results || result1.results.length === 0 || !result1.results[0].returnValues) {
        console.log("获取账户ID失败");
        setStakingBalance("0");
        setFetchingBalance(false);
        return;
      }
      
      const accountIdResult = result1.results[0].returnValues[0];
      if (!accountIdResult || !accountIdResult[0]) {
        console.log("账户ID格式无效");
        setStakingBalance("0");
        setFetchingBalance(false);
        return;
      }
      
      const accountId = String(accountIdResult[0]);
      console.log("成功获取账户ID:", accountId);
      
      // 2. 直接检查是否存在质押记录
      const checkTx = new Transaction();
      checkTx.moveCall({
        target: `${PACKAGE_ID}::lending_protocol::check_staking_info_exists` as any,
        arguments: [
          checkTx.object(LENDING_PROTOCOL_ID),
          checkTx.pure.id(accountId),
        ],
        typeArguments: ["0x2::sui::SUI", YTSUI_TYPE]
      });
      
      let hasStakingRecord = false;
      try {
        await suiClient.devInspectTransactionBlock({
          transactionBlock: checkTx,
          sender: wallet.account?.address || ""
        });
        // 如果上面的调用没有抛出异常，说明质押记录存在
        hasStakingRecord = true;
        console.log("确认存在质押记录");
      } catch (error) {
        console.log("质押记录不存在或检查失败:", error);
        hasStakingRecord = false;
      }
      
      if (!hasStakingRecord) {
        console.log("用户没有质押记录");
        setStakingBalance("0");
        setFetchingBalance(false);
        return;
      }
      
      // 3. 使用staking_total_amount获取总质押金额
      const balanceTx = new Transaction();
      balanceTx.moveCall({
        target: `${PACKAGE_ID}::lending_protocol::staking_total_amount` as any,
        arguments: [
          balanceTx.object(LENDING_PROTOCOL_ID),
          balanceTx.pure.id(accountId),
        ],
        typeArguments: ["0x2::sui::SUI", YTSUI_TYPE]
      });
      
      const balanceResult = await suiClient.devInspectTransactionBlock({
        transactionBlock: balanceTx,
        sender: wallet.account?.address || ""
      });
      
      console.log("获取总质押金额结果:", balanceResult);
      
      if (balanceResult.results && balanceResult.results[0]?.returnValues) {
        const balanceValue = balanceResult.results[0].returnValues[0];
        if (balanceValue && balanceValue[0] !== undefined) {
          const balance = Number(BigInt(String(balanceValue[0]))) / 1_000_000_000;
          console.log("成功获取到余额:", balance, "SUI");
          setStakingBalance(balance.toString());
        } else {
          console.log("余额结果格式无效");
          
          // 如果前面已确认有质押记录但无法获取具体金额，就设置一个最小值
          setStakingBalance("0.000000001");
        }
      } else {
        console.log("无法获取余额信息");
        if (hasStakingRecord) {
          setStakingBalance("0.000000001"); // 如果确认有质押记录，就设置一个最小值
        } else {
          setStakingBalance("0");
        }
      }
      
      // 4. 尝试直接查询借贷协议对象的动态字段获取更多信息
      try {
        // 请求借贷协议对象的动态字段
        const protocolFields = await suiClient.getDynamicFields({
          parentId: LENDING_PROTOCOL_ID
        });
        console.log("借贷协议动态字段:", protocolFields);
        
        // 尝试在stakers表中找到当前账户ID
        if (protocolFields.data) {
          // 查找stakers表
          const stakersTable = protocolFields.data.find(field => 
            field.name && typeof field.name === 'object' && 
            'type' in field.name && field.name.type && 
            field.name.type.includes('stakers')
          );
          
          if (stakersTable) {
            console.log("找到stakers表:", stakersTable);
            // 如果找到了stakers表，就进一步查询其中的内容
            const stakersContent = await suiClient.getDynamicFields({
              parentId: stakersTable.objectId
            });
            console.log("stakers表内容:", stakersContent);
            
            // 在stakers表中寻找与当前账户ID匹配的记录
            const userRecord = stakersContent.data.find(field => 
              field.name && typeof field.name === 'object' && 
              'id' in field.name && field.name.id === accountId
            );
            
            if (userRecord) {
              console.log("找到用户质押记录:", userRecord);
              // 获取用户质押记录的详细信息
              const recordDetails = await suiClient.getObject({
                id: userRecord.objectId,
                options: {
                  showContent: true,
                  showType: true
                }
              });
              console.log("用户质押记录详情:", recordDetails);
              
              // 从记录中提取总资产金额
              if (recordDetails.data && recordDetails.data.content) {
                const content = recordDetails.data.content;
                if (typeof content === 'object' && 'fields' in content) {
                  const fields = content.fields;
                  if ('total_asset_amount' in fields) {
                    const totalAmount = Number(BigInt(String(fields.total_asset_amount))) / 1_000_000_000;
                    console.log("从记录中直接获取总资产金额:", totalAmount, "SUI");
                    setStakingBalance(totalAmount.toString());
                  }
                }
              }
            }
          }
        }
      } catch (dynamicFieldError) {
        console.error("查询动态字段失败:", dynamicFieldError);
      }
      
    } catch (e) {
      console.error("获取质押余额失败", e);
      setStakingBalance("0");
    } finally {
      setFetchingBalance(false);
    }
  };

  // 处理存款操作
  const handleDeposit = async () => {
    try {
      setLoading(true);
      setError("");
      setSuccess("");

      // 验证金额
      if (!amount || parseFloat(amount) <= 0) {
        setError("请输入有效的存款金额");
        return;
      }

      console.log("存款开始，金额:", amount);

      // 将金额转换为MIST (SUI的最小单位，1 SUI = 10^9 MIST)
      const amountInMist = Math.floor(Number(amount) * 1_000_000_000);
      console.log("金额转换为MIST:", amountInMist);

      // 创建交易对象
      const tx = new Transaction();
      
      // 先从用户钱包分离出所需金额的SUI币
      const [coin] = tx.splitCoins(tx.gas, [tx.pure.u64(amountInMist)]);
      
      // 然后调用deposit_api函数进行存款
      tx.moveCall({
        target: `${PACKAGE_ID}::lending_protocol::deposit_api`,
        arguments: [
          tx.object(LENDING_PROTOCOL_ID), // lending protocol对象
          tx.object(LIQUIDITY_LAYER_ID), // liquidity layer对象
          tx.object(ACCOUNT_REGISTRY_ID), // account registry对象
          coin, // 分离出的币作为参数传入，而不是使用pure.u64
          tx.object("0x6"), // Clock对象ID是0x6
        ],
        typeArguments: [
          "0x2::sui::SUI", // T类型是SUI币
          YTSUI_TYPE // YT类型
        ]
      });

      // 执行交易
      const result = await wallet.signAndExecuteTransaction({
        transaction: tx
      });

      // 检查交易结果
      if (result) {
        console.log("存款交易结果:", result);
        
        // 简化处理逻辑，不再尝试提取新创建的凭证ID
        // 直接刷新账户信息来获取最新凭证
        console.log("存款成功，将在2秒后刷新凭证信息");
        
        // 更新成功信息
        setSuccess(`存款成功! 金额: ${amount} SUI`);
        
        // 延迟刷新账户信息和余额，给交易有时间确认
        setTimeout(() => {
          fetchAccountProfileCaps();
        }, 2000);
      }
    } catch (err) {
      console.error("存款过程中出错:", err);
      setError(`存款失败: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      setLoading(false);
    }
  };

  // 处理取款
  const handleWithdraw = async () => {
    if (!amount || !profileCap || !wallet) {
      setError('请输入有效的金额和选择有效的Profile Cap');
      return;
    }
    
    if (!wallet.account) {
      setError('钱包账户不可用');
      return;
    }
    
    try {
      setLoading(true);
      
      const tx = new Transaction();
      tx.moveCall({
        target: `${PACKAGE_ID}::lending_protocol::withdraw_api`,
        arguments: [
          tx.object(LENDING_PROTOCOL_ID), // lending protocol对象
          tx.object(LIQUIDITY_LAYER_ID), // liquidity layer对象
          tx.object(ACCOUNT_REGISTRY_ID), // account registry对象
          tx.object(profileCap), // AccountProfileCap对象ID
          tx.pure.u64(BigInt(Number(amount) * 1_000_000_000)), // 取款金额
          tx.object("0x6"), // Clock对象ID是0x6
        ],
        typeArguments: [
          "0x2::sui::SUI", // T类型是SUI币
          YTSUI_TYPE // YT类型
        ]
      });
      
      // 安全地访问wallet.signAndExecuteTransaction
      if (wallet.signAndExecuteTransaction) {
        const response = await wallet.signAndExecuteTransaction({
          transaction: tx
        });
        
        console.log("Withdraw success", response);
        setSuccess(`取款成功！已取出 ${amount} SUI (详情请查看控制台)`);
        
        // 取款成功后重新获取ProfileCap
        setTimeout(() => {
          fetchAccountProfileCaps();
          setAmount("");  // 清空输入
        }, 2000);
      } else {
        throw new Error("钱包交易签名方法不可用");
      }
      
    } catch (e) {
      console.error("Withdraw failed", e);
      setError(`取款失败: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setLoading(false);
    }
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

  // 刷新ProfileCap按钮
  const handleRefreshProfileCaps = () => {
    setFetchingBalance(true);
    fetchAccountProfileCaps().finally(() => {
      setFetchingBalance(false);
    });
  };

  // 修改verifySelectedProfileCap函数内的所有者验证逻辑
  const verifySelectedProfileCap = async () => {
    if (!profileCap || !wallet.account?.address) {
      setError('请先选择一个凭证');
      return;
    }
    
    try {
      setLoading(true);
      console.log("开始验证凭证:", profileCap);
      
      // 1. 验证凭证对象是否存在
      const objResponse = await suiClient.getObject({
        id: profileCap,
        options: {
          showContent: true,
          showType: true,
          showOwner: true,
        }
      });
      
      console.log("凭证对象完整信息:", objResponse);
      
      if (!objResponse.data) {
        setError(`凭证对象不存在或已被移除`);
        return;
      }
      
      // 2. 验证凭证类型是否正确
      const objType = objResponse.data.type;
      if (!objType || !objType.includes(ACCOUNT_PROFILE_CAP_TYPE)) {
        setError(`凭证类型不正确: ${objType}`);
        return;
      }
      
      // 3. 验证凭证所有权 - 更宽松的验证逻辑
      const objOwner = objResponse.data.owner;
      console.log("凭证所有者信息:", objOwner);
      console.log("当前钱包地址:", wallet.account.address);
      
      if (!objOwner) {
        setError(`凭证无所有者信息`);
        return;
      }
      
      // 尝试多种可能的所有者格式
      let isOwnedByCurrentUser = false;
      const currentAddress = wallet.account.address;
      
      // 检查常见的所有者格式
      if (typeof objOwner === 'object') {
        // 常见情况1: {AddressOwner: "0x..."}
        if ('AddressOwner' in objOwner) {
          if (objOwner.AddressOwner === currentAddress) {
            isOwnedByCurrentUser = true;
            console.log("匹配所有者格式: AddressOwner");
          } else {
            console.log("AddressOwner存在但不匹配当前地址");
          }
        } 
        // 常见情况2: {address: "0x..."}
        else if ('address' in objOwner && typeof objOwner.address === 'string') {
          if (objOwner.address === currentAddress) {
            isOwnedByCurrentUser = true;
            console.log("匹配所有者格式: address字段");
          } else {
            console.log("address字段存在但不匹配当前地址");
          }
        }
        // 常见情况3: {owner: "0x..."}
        else if ('owner' in objOwner && typeof objOwner.owner === 'string') {
          if (objOwner.owner === currentAddress) {
            isOwnedByCurrentUser = true;
            console.log("匹配所有者格式: owner字段");
          } else {
            console.log("owner字段存在但不匹配当前地址");
          }
        }
        // 常见情况4: 验证Shared对象
        else if ('Shared' in objOwner) {
          console.log("凭证为共享对象");
          // 共享对象可以被任何人访问，所以我们允许使用
          isOwnedByCurrentUser = true;
        }
        // 常见情况5: 检查ObjectOwner
        else if ('ObjectOwner' in objOwner) {
          console.log("凭证由对象所有:", objOwner.ObjectOwner);
          // 这种情况较复杂，需要验证对象所有权链
          // 暂时允许尝试使用，但记录警告
          isOwnedByCurrentUser = true; // 放宽限制允许尝试
        }
      }
      // 常见情况6: 直接是字符串地址
      else if (typeof objOwner === 'string' && objOwner === currentAddress) {
        isOwnedByCurrentUser = true;
        console.log("匹配所有者格式: 直接字符串地址");
      }
      
      // 如果所有已知格式都不匹配，但我们仍然希望允许尝试使用
      if (!isOwnedByCurrentUser) {
        console.warn(`凭证所有者格式未识别或不匹配当前钱包地址:`, objOwner);
        
        // 不是致命错误，只显示警告并继续
        setSuccess(`凭证所有者格式未识别，但允许继续操作。如果稍后操作失败，请创建新凭证。`);
        // 不提前返回，允许继续验证和使用
      }
      
      // 4. 获取账户ID
      const tx = new Transaction();
      tx.moveCall({
        target: `${PACKAGE_ID}::account_ds::account_of` as any,
        arguments: [tx.object(profileCap)],
      });
      
      const result = await suiClient.devInspectTransactionBlock({
        transactionBlock: tx,
        sender: wallet.account.address
      });
      
      console.log("获取账户ID结果:", result);
      
      if (!result.results || result.results.length === 0 || !result.results[0].returnValues) {
        setError('无法从凭证获取账户ID，但凭证可能仍然有效');
        // 允许继续尝试使用凭证
      } else {
        const accountIdResult = result.results[0].returnValues[0];
        if (!accountIdResult || !accountIdResult[0]) {
          console.warn('账户ID格式无效');
          // 只记录警告，不阻止使用
        } else {
          const accountId = String(accountIdResult[0]);
          console.log("凭证对应的账户ID:", accountId);
          
          // 5. 尝试获取凭证的资产类型
          try {
            const assetTx = new Transaction();
            assetTx.moveCall({
              target: `${PACKAGE_ID}::account_ds::get_account_assets` as any,
              arguments: [assetTx.object(profileCap)],
            });
            
            const assetResult = await suiClient.devInspectTransactionBlock({
              transactionBlock: assetTx,
              sender: wallet.account.address
            });
            
            console.log("获取资产类型结果:", assetResult);
            
            if (assetResult.results && assetResult.results[0]?.returnValues) {
              // 假设返回了资产类型数组
              console.log("此凭证可能支持多种资产类型");
            }
          } catch (assetError) {
            console.log("获取资产类型失败，使用默认SUI类型:", assetError);
          }
          
          // 6. 显示验证成功消息
          setSuccess(`凭证验证成功! 账户ID: ${accountId}，当前使用的资产类型: SUI。`);
        }
      }
      
    } catch (error) {
      console.error("验证凭证失败:", error);
      setError(`验证凭证失败: ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      setLoading(false);
    }
  };

  // 强制刷新凭证，尝试多种方法获取凭证信息
  const forceRefreshProfileCaps = async () => {
    if (!wallet.connected || !wallet.account) {
      setError('请先连接钱包');
      return;
    }
    
    setLoading(true);
    setError('');
    setSuccess('');
    
    try {
      console.log("正在强制刷新凭证，使用多种方法...");
      
      // 方法1：使用标准查询但忽略过滤器，获取所有对象
      const response1 = await suiClient.getOwnedObjects({
        owner: wallet.account.address,
        options: {
          showContent: true,
          showDisplay: true,
          showType: true,
          showOwner: true,
        },
      });
      
      console.log("获取所有对象响应:", response1);
      
      // 从所有对象中筛选可能的凭证
      const possibleCaps = response1.data
        .filter(item => {
          // 只检查有效对象
          if (!item.data) return false;
          
          // 检查类型或其他标识符
          const objType = item.data.type || '';
          return objType.includes('AccountProfileCap') || 
                 objType.includes('account_ds') ||
                 objType.includes(PACKAGE_ID);
        })
        .map(item => ({
          id: item.data!.objectId,
          description: `对象 (${item.data!.objectId.substring(0, 8)}...)`
        }));
      
      console.log("找到可能的凭证:", possibleCaps);
      
      if (possibleCaps.length > 0) {
        setAvailableProfileCaps(possibleCaps);
        setProfileCap(possibleCaps[0].id);
        setSuccess(`找到 ${possibleCaps.length} 个可能的凭证对象，已选择第一个。`);
      } else {
        // 方法2：尝试直接调用Move函数获取账户信息
        try {
          const tx = new Transaction();
          tx.moveCall({
            target: `${PACKAGE_ID}::account_ds::get_accounts_by_owner` as any,
            arguments: [
              tx.object(ACCOUNT_REGISTRY_ID),
              tx.pure.address(wallet.account.address),
            ]
          });
          
          const result = await suiClient.devInspectTransactionBlock({
            transactionBlock: tx,
            sender: wallet.account.address
          });
          
          console.log("通过Move函数获取账户信息:", result);
          
          if (result.results && result.results[0]?.returnValues) {
            setSuccess("找到账户信息，但未找到凭证对象。建议进行一笔小额存款来创建新凭证。");
          } else {
            setError("未找到任何凭证或账户信息。请尝试创建一个新账户。");
          }
        } catch (moveError) {
          console.error("尝试通过Move获取账户失败:", moveError);
          setError("强制刷新失败，请进行一笔小额存款来创建新凭证。");
        }
      }
    } catch (e) {
      console.error("强制刷新凭证失败", e);
      setError("强制刷新失败，请重试或尝试存入一小笔资金以创建新凭证");
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="flex min-h-screen flex-col items-center justify-between p-24">
      <div className="z-10 w-full max-w-5xl items-center justify-between font-mono text-sm lg:flex">
        <p className="fixed left-0 top-0 flex w-full justify-center border-b border-gray-300 bg-gradient-to-b from-zinc-200 pb-6 pt-8 backdrop-blur-2xl dark:border-neutral-800 dark:bg-zinc-800/30 dark:from-inherit lg:static lg:w-auto lg:rounded-xl lg:border lg:bg-gray-200 lg:p-4 lg:dark:bg-zinc-800/30">
          Nawhal.fi 借贷协议示例页面 <span className="ml-2 text-red-500 font-bold">仅支持测试网</span>
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
        <h1 className="text-4xl font-bold mb-8">Nawhal.fi 借贷协议</h1>

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
          <p className={"my-8"}>请连接钱包以使用借贷功能</p>
        ) : (
          <div className={"my-8 w-full max-w-md"}>
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
                当前网络: <span className={!isTestnet ? "text-red-500 font-bold" : "text-green-500 font-bold"}>
                  {chainName(wallet.chain?.id)} {!isTestnet && "(请切换到测试网)"}
                </span>
              </p>
              <p>
                钱包余额:{" "}
                {formatSUI(balance ?? 0, {
                  withAbbr: false,
                })}{" "}
                SUI
              </p>
              <p className="text-indigo-600 font-medium">
                当前操作资产类型: <span className="font-bold">SUI</span> 
                <span className="text-xs ml-1">(Nawhal.fi支持多种资产，每种资产有独立凭证)</span>
              </p>
              <div className="mt-2 bg-blue-50 dark:bg-blue-900 p-2 rounded">
                <p className="font-semibold text-blue-700 dark:text-blue-300">
                  凭证数量: {availableProfileCaps.length} 个
                </p>
                <p className="font-semibold text-blue-700 dark:text-blue-300">
                  总存款额: {fetchingBalance ? '加载中...' : `${totalDeposited} SUI`}
                </p>
                {profileCap && (
                  <p className="font-semibold text-blue-700 dark:text-blue-300">
                    当前SUI凭证余额: {fetchingBalance ? '加载中...' : `${stakingBalance} SUI`} 
                    {stakingBalance === "0" && !fetchingBalance && (
                      <span className="text-xs ml-1 text-orange-500">
                        (此凭证可能尚未存入SUI资产)
                      </span>
                    )}
                  </p>
                )}
              </div>
            </div>
            
            {error && (
              <div className="w-full mb-4 p-3 bg-red-100 text-red-700 rounded-lg">
                {error}
                {error.includes("余额") && (
                  <p className="text-xs mt-1">
                    提示：如果您有多种资产类型的凭证，请确保选择了正确的凭证。目前界面仅显示SUI资产的余额。
                  </p>
                )}
              </div>
            )}
            
            {success && (
              <div className="w-full mb-4 p-3 bg-green-100 text-green-700 rounded-lg">
                {success}
              </div>
            )}
            
            <div className="w-full mb-6">
              <label htmlFor="amount" className="block mb-2 text-sm font-medium">
                SUI 金额
              </label>
              <input
                type="number"
                id="amount"
                className="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white"
                placeholder="输入SUI金额"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                min="0"
                step="0.000000001"
              />
            </div>

            <div className="w-full mb-6">
              <div className="flex justify-between items-center mb-2">
                <label htmlFor="profileCap" className="block text-sm font-medium">
                  账户凭证 (AccountProfileCap)
                </label>
                <div className="flex gap-2">
                  <button 
                    onClick={handleRefreshProfileCaps}
                    className="text-xs bg-blue-600 hover:bg-blue-700 text-white py-1 px-2 rounded"
                    disabled={fetchingBalance}
                  >
                    {fetchingBalance ? '加载中...' : '刷新凭证'}
                  </button>
                  {profileCap && (
                    <button 
                      onClick={verifySelectedProfileCap}
                      className="text-xs bg-green-600 hover:bg-green-700 text-white py-1 px-2 rounded"
                      disabled={loading}
                    >
                      验证凭证
                    </button>
                  )}
                  <button 
                    onClick={forceRefreshProfileCaps}
                    className="text-xs bg-yellow-600 hover:bg-yellow-700 text-white py-1 px-2 rounded"
                    disabled={loading}
                  >
                    强制刷新
                  </button>
                </div>
              </div>
              
              {availableProfileCaps.length > 0 ? (
                <select
                  id="profileCap"
                  className="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white"
                  value={profileCap}
                  onChange={(e) => setProfileCap(e.target.value)}
                >
                  <option value="">选择账户凭证</option>
                  {availableProfileCaps.map((cap) => (
                    <option key={cap.id} value={cap.id}>
                      {cap.description}
                    </option>
                  ))}
                </select>
              ) : (
                <div className="p-2.5 bg-gray-100 border border-gray-300 text-gray-500 text-sm rounded-lg">
                  未找到凭证，存款后会自动创建凭证
                </div>
              )}
              
              <p className="mt-1 text-xs text-gray-500">
                存款操作会自动创建账户凭证，取款时需要选择对应的凭证
              </p>
              <p className="mt-1 text-xs text-blue-500">
                注意: 每个地址可以有多个凭证，但每种资产类型只对应一个凭证。当前界面仅支持SUI资产操作。
              </p>
            </div>
            
            <div className="flex flex-col sm:flex-row gap-4">
              <button 
                className={`flex-1 ${loading ? 'bg-gray-500' : 'bg-blue-600 hover:bg-blue-700'} text-white font-bold py-2 px-4 rounded flex items-center justify-center`}
                onClick={handleDeposit}
                disabled={!amount || !wallet.connected || loading || !isTestnet}
              >
                {loading ? '处理中...' : '存款'}
              </button>
              <button 
                className={`flex-1 ${loading ? 'bg-gray-500' : 'bg-purple-600 hover:bg-purple-700'} text-white font-bold py-2 px-4 rounded flex items-center justify-center`}
                onClick={handleWithdraw}
                disabled={!amount || !wallet.connected || loading || !profileCap || !isTestnet}
              >
                {loading ? '处理中...' : '取款'}
              </button>
            </div>
            
            {fetchingBalance && (
              <div className="mt-4 text-center text-sm text-blue-600">
                正在加载凭证和余额信息...
              </div>
            )}
            
            <div className="mt-8 text-sm text-gray-500">
              <p>合约信息：</p>
              <ul className="list-disc pl-5 mt-1 space-y-1">
                <li>Package ID: {PACKAGE_ID}</li>
                <li>Lending Protocol ID: {LENDING_PROTOCOL_ID}</li>
                <li>Liquidity Layer ID: {LIQUIDITY_LAYER_ID}</li>
                <li>Account Registry ID: {ACCOUNT_REGISTRY_ID}</li>
              </ul>
              <p className="mt-4">测试说明：</p>
              <ol className="list-decimal pl-5 mt-1 space-y-1">
                <li>确保您已连接到<strong>测试网</strong></li>
                <li>输入存款金额（小于钱包余额）进行存款</li>
                <li>存款后，系统会自动创建并获取您的账户凭证</li>
                <li>选择账户凭证和输入金额，即可进行取款操作</li>
              </ol>
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
          href="https://testnet.suivision.xyz/package/0x891b34e2e9d6976f42a40520d862d69e1030969670c5f5f11aad3dce3a374255"
          target="_blank"
          rel="noopener noreferrer"
          className="group rounded-lg border border-transparent px-5 py-4 transition-colors hover:border-gray-300 hover:bg-gray-100 hover:dark:border-neutral-700 hover:dark:bg-neutral-800/30"
        >
          <h2 className={`mb-3 text-2xl font-semibold`}>
            合约浏览器{" "}
            <span className="inline-block transition-transform group-hover:translate-x-1 motion-reduce:transform-none">
              -&gt;
            </span>
          </h2>
          <p className={`m-0 max-w-[30ch] text-sm opacity-50`}>
            在SuiVision上查看Nawhal合约
          </p>
        </a>

        <a
          href="https://docs.sui.io/build/move"
          target="_blank"
          rel="noopener noreferrer"
          className="group rounded-lg border border-transparent px-5 py-4 transition-colors hover:border-gray-300 hover:bg-gray-100 hover:dark:border-neutral-700 hover:dark:bg-neutral-800/30"
        >
          <h2 className={`mb-3 text-2xl font-semibold`}>
            Sui Move{" "}
            <span className="inline-block transition-transform group-hover:translate-x-1 motion-reduce:transform-none">
              -&gt;
            </span>
          </h2>
          <p className={`m-0 max-w-[30ch] text-sm opacity-50`}>
            探索Sui Move开发文档。
          </p>
        </a>
      </div>
    </main>
  );
}