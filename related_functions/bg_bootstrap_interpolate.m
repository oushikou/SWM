function [stats]=bg_bootstrap_interpolate(shapeMat, numIt, frac, verbose, fignum)
% stats = bg_bootstrap_interpolate(shapeMat, numIt, frac, verbose, fignum)
%
% Uses interpolation together with detection of extrema to calculate skweness index based on T_up/T_down ratio.
% Like other bootstrap functions estimates confidence interval of skewness of noisy shapes contained in
% 'shapeMat' using bootstrap resampling.
%
% This method is useful when the individual shapes are very
% noisy, and this noise hinders you in determining the true skewness of
% every shape individually. Averaging over a larg enough (frac) sub sample,
% will average out most of the noise.
%
% Note: this method assumes a unimodal distribution of skewness.
% If the input is a result (a single cluster) from bg_SWM and/or bg_SWM_SA
% this is a fair assumption.
%
% %%%%%%%%%
% input:
% %%%%%%%%%
%
% shapeMat: Matrix of size numShapes x numTimepoints. E.g. the resulting
%           matrices from bg_swm_extract.
%
% numIt:    How many of these resampled distributions should be constructed
%
% frac:     Fraction of total number of samples used every for every bootstrap
%           resample. (i.e. frac*numShapes is the amount of shapes in
%           every subsample)
%           (default = 1; for correct bootstrap statistics this *should be*
%           1)
%
% verbose:  Flag that determines whether the progress (i.e. iteration
%           counter) is written to the terminal/ command window.
%           (default: verbose = 1)
%
% fignum:   (optional) Figure number/handle to which to plot every sample;
%           smoothed together with the 3 detected extrema.
%           If left empty or set to zero, no figure is plotted.
%
% %%%%%%%%%
% output:
% %%%%%%%%%
%
% stats:  a structure containing the calculated statistics:
% firstly it contains two fields for visualization:
% .meanShape: the mean shape used for detecting asymmetry (interpolated)
% .extrema:   the median of the positions of the extrema used for the calculation
%
% stats contains 2 sub structures .skw and .period. These contain the
% statistics on both skewness and period respectively.
%
% These substructures contain the following fields:"
%
% .mu:    Estimated mean
% .sem:   Estimated standard error of .mu
% .distr: Samples generated by the bootstrap procedure that are used to
%         calculate .mu and .sem.
% .p_t:   p-value for student-t test for rejecting the hypothesis that the
%         mean is equal to zero. (alpha =.05)
% .CI:    Similar to .p_t, but now the 95% confidence interval. If this
%         contains zero, H0 cannot be rejected

if nargin<3 || isempty(frac)
  frac=1;
end

if frac~= 1
  warning('The sample size for the bootstrap statistics is not equal to the original sample size. Statistics on the mean will not be correct.')
end

if nargin<4
  verbose=1;
end
reverseStr=[];

if nargin >4 && fignum
  figure(fignum)
  clf
  %   set(fignum,'visible','off')
end



[numTemp, tempLen]=size(shapeMat);

skwIdx=nan(numIt,1);
brd=nan(numIt,3);
sampsz=round(frac*numTemp);

% find bias for bg_skewness_pktg_smooth; i.e. find period with least
% variance
nfft=2^nextpow2(tempLen)*4;
ftshape=fft(nanmean(shapeMat),nfft);
[~,midx]=max(abs(ftshape(1:nfft/2+1)));
shapeLen=round(nfft/midx);
varShape=nanvar(shapeMat);
bias=conv(varShape,ones(1,shapeLen),'valid');
% push shapes towards centre (increase cost of edges by 10%)
parabola=[1:numel(bias)]-numel(bias)/2-.5;
parabola=parabola/parabola(end);
parabola=1+parabola.^2*.1;
[~,bias]=min(bias.*parabola);
bias=[bias bias+shapeLen/2+.5 bias+shapeLen];


for iter=1:numIt
  
  sel=ceil(rand(sampsz,1)*numTemp);
  meanShape=nanmean(shapeMat(sel,:))';
  
  if verbose
    msg=sprintf(['Iteration %d/%d\n'], [iter numIt]);
    fprintf([reverseStr, msg]);
    reverseStr = repmat(sprintf('\b'), 1, length(msg));
  end
  %% calculating SkwIdx
  
    [skwIdx(iter), brd(iter,:), meanShapeInt]=bg_skewness_pktg_smooth(meanShape,bias);
    
    if iter==1
      % make sure that bootstrapping will always focus on the same period
      bias= brd(iter,:)/100;
    end
    
    if nargin >4 && fignum
      current_figure(fignum)
      plot(meanShapeInt)
      vline(brd(iter,:))
      title(sprintf(['Iteration %d/%d\n'], [iter numIt]))
      xlim([1 numel(meanShapeInt)])
      title(['Iteration ' num2str(iter) '/' num2str(numIt) '; Skewness: ' num2str(skwIdx(iter),'%1.3f')])
      drawnow
    end
  
  
  
end



%% skewness
stats.skw.mu=nanmean(skwIdx);
stats.skw.sem=sqrt(numIt/(numIt-1)*nanvar(skwIdx,1));
stats.skw.distr=skwIdx;


% perform t-test on difference from zero (only works if frac=1).
t=stats.skw.mu/stats.skw.sem;
stats.skw.p_t=1-tcdf(abs(t),numIt-1);
% 95% confidence
alpha=.05;
try
  stats.skw.CI= quantile(skwIdx,[alpha/2 1-alpha/2]);
catch
  warning('no confidence interval(s) calculated.')
end

%% period
periods=diff(brd(:,[1 3]),1,2);
stats.period.mu=nanmean(periods);
stats.period.sem=sqrt(numIt/(numIt-1)*nanvar(periods,1));
stats.period.distr=periods;


% perform t-test on difference from zero (only works if frac=1).
t=stats.period.mu/stats.period.sem;
stats.period.p_t=1-tcdf(abs(t),numIt-1);
% 95% confidence
alpha=.05;
try
  stats.period.CI= quantile(periods,[alpha/2 1-alpha/2]);
end

%% mean extrema positions and shape
stats.extrema=[quantile(brd(:,1),.5) quantile(brd(:,2),.5) quantile(brd(:,3),.5)];
cutout_dum=stats.extrema([1 3]);
cutout_dum=round(cutout_dum+[-1 1]*.25*diff(cutout_dum));
meanShapeDum=nanmean(shapeMat)';
t=1:tempLen;
tint=linspace(1,tempLen,numel(meanShapeInt));
stats.meanShape=spline(t',meanShapeDum,tint');
% cutout_dum=max(cutout_dum,1);
% cutout_dum=min(cutout_dum,numel(tint));
% stats.meanShape=stats.meanShape(cutout_dum(1):cutout_dum(2));
% stats.extrema=stats.extrema-cutout_dum(1)+1;

function current_figure(h)
set(0,'CurrentFigure',h)


function Y=quantile(x, p)
% only takes vectors
x=x(~isnan(x));
x=sort(x,1);
L=size(x,1);
Y=nan(numel(p),1);
for n=1:numel(p)
  idx=p(n)*(L-.5)+.5;
  remainder=rem(idx,1);
  Y(n)=(1-remainder)*x(floor(idx))+(remainder)*x(floor(idx)+1);
end




