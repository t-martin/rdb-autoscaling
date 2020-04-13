// asg/sub.q

/ called by the tickerplant when it begins publishing to the process
/ schemas   - table names and schemas of subscription tables
/ tplog     - file path of the tickerplant log
/ logWindow - start and end of the window needed in the log, (start;end)
.sub.rep:{[schemas;tplog;logWindow]
    .util.lg "Tickerplant has made process the live subscriber";
    .util.lg "Replaying ",string[tplog]," between ", .Q.s1 logWindow;

    .sub.live: 1b;
    (.[;();:;].) each schemas;
    .sub.start: logWindow 0;
    `upd set .sub.replayUpd;
    -11!(logWindow 1;tplog);
    `upd set .sub.upd;
 };

/ upd wrapper
/ only adds data from log window
/ monitors memory every 100 messages
.sub.replayUpd:{[t;data]
    if[.sub.i > .sub.start;
        .sub.upd[t;flip data];
        if[not .sub.i mod 100;
                .util.lg "Replayed ",string[.sub.i]," messages";

                .sub.monitorMemory[]];
        :(::);
        ];
    .sub.i+: 1;
 };

/ regular upd function
/ must keep track of upd message count
.sub.upd: {.sub.i+: 1; x upsert y;};

/ monitor server memory
/ check if a new server needs to be launched
/ then check if the process needs to unsubscribe
.sub.monitorMemory:{[]
    if[not .sub.scaled;
        if[.util.getMemUsage[] > .sub.scaleThreshold;
                .util.lg "Server has reached ",string[.sub.scaleThreshold],"% memory usage";
                .util.lg "Scaling the Auto Scaling group";

                .util.aws.scale .aws.groupName;
                .sub.scaled: 1b;
                ];
        :(::);
        ];
    if[.sub.live;
        if[.util.getMemUsage[] > .sub.rollThreshold;
                .util.lg "Server has reached ",string[.sub.rollThreshold],"% memory usage";

                .sub.roll[];
                ];
        ];
    if[.sub.scaled and not max 0, count each get each tables[];
            .util.lg "Process has rolled and has no data left";
            .util.lg "Terminating instance from Auto Scaling group";

            .util.aws.terminate .aws.instanceId;
        ];
 };

/ send tickerplant last upd message processed and unsubscribe
.sub.roll:{[]
    .util.lg "Unsubscribing from the Tickerplant";

    .sub.live: 0b;
    `upd set {[x;y] (::)};
    neg[.sub.TP] @ ({.u.asg.roll[.z.w;x]}; .sub.i);
 };

.sub.end:{[dt]
    .sub.i: 0;
    .sub.clear dt+1;
 };

/ clear data from all tables from before a certain time
/ terminate the the server if no data is left and the process has cut its subscription
/ tm - clear all data from all tables before this time
.sub.clear:{[tm]
    .util.lg "Clearing data from before ", string tm;

    ![;enlist(<;`time;tm);0b;`$()] each tables[];

    if[.sub.live;
            .sub.scaled:0b;
            .Q.gc[];
            :(::);
            ];

    if[not max 0, count each get each tables[];
            .util.lg "Process has rolled and has no data left";
            .util.lg "Terminating instance from Auto Scaling group";

            .util.aws.terminate .aws.instanceId;
            ];

 };
