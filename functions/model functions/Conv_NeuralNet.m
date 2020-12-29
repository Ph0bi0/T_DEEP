function RES = Conv_NeuralNet(TrainMCS,TestMCS,CNNpar,CNN_TrainOpt,RNG)

% FUNCTION OVERVIEW
%{
This functions performs training and testing of a Convolutional Neural
Network model.
This model takes as input the multichannel spectrograms contained in the
structs "TrainMCS" and "TestMCS".
The function returns a struct "RES" containing as many fields as the k-fold
cross validation used to partition the data in "TrainMCS" and "TestMCS",
plus one extrafield with the resulting confusion matrix of the entire
k-fold cross validation process.
Each field of "RES" corresponding to cross validation folders contains 4
fields:
    - TrainingTime, with the time in milliseconds required to train the
    model corresponding to the folder
    - TestingTime, with the time in milliseconds required to test the
    model corresponding to the folder
    - Model, with the Convolutional Neural Network resulting from the
    training process performed on the corresponding folder
    - ConfusionMat, containing the confusion matrix resulting from the
    testing of the model on the correspoding folder

The architecture of the net is defined by the array "layer" and the
convolution2dLayer is construced according to the parameter contained in
the input struct "CNNpar".

The training options are defined in the object "opt" accordingly to the
input cell "CNN_TrainOpt".

The validation set is constructed using the matlab function "cvpartition"
and the random process is governed by the input struct "RNG".

The partitioned dataset contained in the input structs "TrainMCS" and
"TestMCS" is at first rearranged in "XTrain", "XValid", "XTest", "YTrain",
"YValid" and "YTest" then passed to the matlab function "trainNetwork" to
perform the training process.

Testing of the model is performed using the matlab function "classify".
%}

% assign the training options to appropriate variables
for i = 1:size(CNN_TrainOpt,1)
    switch CNN_TrainOpt{i,1}
        case 'valid_perc'
            valid_perc = CNN_TrainOpt{i,2};
        case 'init_learn_rate'
            init_learn_rate = CNN_TrainOpt{i,2};
        case 'learn_drop_factor'
            learn_drop_factor = CNN_TrainOpt{i,2};
        case 'max_epochs'
            max_epochs = CNN_TrainOpt{i,2};
        case 'minibatch_size'
            minibatch_size = CNN_TrainOpt{i,2};
        case 'valid_patience'
            valid_patience = CNN_TrainOpt{i,2};
        case 'valid_frequency'
            valid_frequency = CNN_TrainOpt{i,2};
    end
end

FN = fieldnames(TrainMCS);
Kfold = numel(FN);

% define the architecture of CNN
InSize = size(TrainMCS.(FN{1}).data{1});
TotLabl = [TrainMCS.(FN{1}).labl;TestMCS.(FN{1}).labl];
NumTer = max(double(TotLabl));

layers = [
    imageInputLayer(InSize,'Name','inLayer')
    batchNormalizationLayer('Name','batchNorm')
    convolution2dLayer(CNNpar.FilterSize,CNNpar.numFilters,'Padding','same','Name','conv2d1')
    reluLayer('Name','ReluLayer')

    fullyConnectedLayer(NumTer,'Name','Fullconnect')
    softmaxLayer('Name','SoftLayer')
    classificationLayer('Name','ClassificationLayer')];

% find validation indexes
iValid = cell(Kfold,1);
for i = 1:Kfold
    rng(RNG.seed,RNG.generator)
    cvp = cvpartition(size(TrainMCS.(FN{i}).labl,1),'HoldOut',valid_perc);
    iValid{i} = cvp.test;
end

% arrange the data how the training function requires them, train and test
% the model

for i = 1:Kfold
    BatchSize = size(TrainMCS.(FN{i}).data,1);
    for j = 1:BatchSize
        XTrain0(:,:,:,j) = TrainMCS.(FN{i}).data{j};
    end
    YTrain0 = TrainMCS.(FN{i}).labl;
    
    BatchSize = size(TestMCS.(FN{i}).data,1);
    for j = 1:BatchSize
        XTest(:,:,:,j) = TestMCS.(FN{i}).data{j};
    end
    YTest = TestMCS.(FN{i}).labl;
    
    XTrain = XTrain0(:,:,:,~iValid{i});
    XValid = XTrain0(:,:,:,iValid{i});
    YTrain = YTrain0(~iValid{i});
    YValid = YTrain0(iValid{i});
    
    % define training options

    opt = trainingOptions('adam', ...
            'ExecutionEnvironment','cpu', ...
            'GradientThreshold',1, ...
            'InitialLearnRate',init_learn_rate, ...
            'LearnRateSchedule','piecewise', ...
            'Verbose',0,...
            'LearnRateDropFactor',learn_drop_factor, ...
            'MaxEpochs',max_epochs, ...
            'MiniBatchSize',minibatch_size, ...
            'ValidationData',{XValid,YValid}, ...
            'ValidationPatience', valid_patience, ...
            'ValidationFrequency',valid_frequency, ...   
            'SequenceLength','longest', ...
            'Shuffle','every-epoch', ...
            'Plots','none');
    
    % Train CNN
    disp(strcat('CNN Training Partition = ',num2str(i)))
    
    tic
    CNN = trainNetwork(XTrain,YTrain,layers,opt);
    % store results
    RES.(FN{i}).TrainingTime = toc;
    RES.(FN{i}).Model = CNN;
    
    % Test CNN
    
    tic
    YPred = classify(CNN,XTest);
    % store results
    RES.(FN{i}).TestingTime = toc;
    RES.(FN{i}).ConfusionMat = confusionmat(YTest,YPred);
    
    % clear variables for the next folder
    clear XTrain0 XTrain XValid XTest
    clear YTrain0 YTrain YValid YTest
    clear YPred
end

% compute the confusion matrix of the k-fold cross validation process
CM = RES.(FN{1}).ConfusionMat;
for i = 2:Kfold
    CM = CM + RES.(FN{i}).ConfusionMat;
end

% store the results
RES.ConfusionMat = CM;


    
end